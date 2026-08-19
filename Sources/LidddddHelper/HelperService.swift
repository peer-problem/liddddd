import Foundation
import LidddddCore

final class HelperService: NSObject, LidddddHelperProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private let power = PowerController()
  private let store = SessionStore()
  private var record: SessionRecord?
  private var safetyTimer: DispatchSourceTimer?
  private var lastTemperatureCelsius: Double?
  private var lastStopEvent: StopEvent?

  override init() {
    super.init()
    lastStopEvent = try? store.loadLastStop()
    recoverOrResumeSession()
  }

  func status(withReply reply: @escaping (Data) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    enforceSafetyPolicy()
    reply(HelperCodec.encode(makeReply(success: true)))
  }

  func start(
    durationSeconds: Double,
    batteryFloor: Int,
    withReply reply: @escaping (Data) -> Void
  ) {
    lock.lock()
    defer { lock.unlock() }

    do {
      try SessionPolicy.validate(duration: durationSeconds, batteryFloor: batteryFloor)
      enforceSafetyPolicy()

      guard record == nil else {
        reply(
          HelperCodec.encode(makeReply(success: false, message: "Liddddd is already on.")))
        return
      }
      guard try !power.isSleepDisabled() else {
        reply(
          HelperCodec.encode(
            makeReply(
              success: false,
              message: "Another app or command already turned off Mac sleep."
            )))
        return
      }

      guard let battery = power.batteryPercent() else {
        reply(
          HelperCodec.encode(
            makeReply(
              success: false,
              message: "Liddddd could not check your battery level."
            )))
        return
      }
      if battery <= batteryFloor {
        reply(
          HelperCodec.encode(
            makeReply(
              success: false,
              message: "Your battery is already at or below the stop level."
            )))
        return
      }
      let thermalState = power.thermalState()
      guard thermalState != .serious, thermalState != .critical else {
        reply(
          HelperCodec.encode(
            makeReply(
              success: false,
              message: "Your Mac is already too hot to start Liddddd."
            )))
        return
      }

      let temperature = power.maximumDieTemperatureCelsius()
      lastTemperatureCelsius = temperature
      if let temperature,
        case .stop = SessionPolicy.evaluateTemperature(temperatureCelsius: temperature)
      {
        reply(
          HelperCodec.encode(
            makeReply(
              success: false,
              message: String(
                format: "The Mac is already at %.1f°C, at or above the 90°C cutoff.", temperature
              )
            )))
        return
      }

      let now = Date()
      let systemUptime = ProcessInfo.processInfo.systemUptime
      let newRecord = SessionRecord(
        startedAt: now,
        endDate: now.addingTimeInterval(durationSeconds),
        batteryFloor: batteryFloor,
        originalSleepDisabled: false,
        bootSessionIdentifier: Self.bootSessionIdentifier(),
        endSystemUptime: systemUptime + durationSeconds
      )

      try store.save(newRecord)
      do {
        try power.setSleepDisabled(true)
        try power.beginIdleSleepAssertion()
      } catch {
        try? power.setSleepDisabled(false)
        try? store.clear()
        throw error
      }

      record = newRecord
      lastStopEvent = nil
      try? store.clearLastStop()
      startSafetyTimer()
      reply(HelperCodec.encode(makeReply(success: true)))
    } catch {
      reply(HelperCodec.encode(makeReply(success: false, message: error.localizedDescription)))
    }
  }

  func stop(withReply reply: @escaping (Data) -> Void) {
    lock.lock()
    defer { lock.unlock() }

    do {
      try stopManagedSession(reason: .user)
      reply(HelperCodec.encode(makeReply(success: true)))
      scheduleCleanExit()
    } catch {
      reply(HelperCodec.encode(makeReply(success: false, message: error.localizedDescription)))
    }
  }

  func restoreNormalSleep(withReply reply: @escaping (Data) -> Void) {
    lock.lock()
    defer { lock.unlock() }

    guard record == nil else {
      reply(
        HelperCodec.encode(
          makeReply(
            success: false,
            message: "Turn off Liddddd first."
          )))
      return
    }

    do {
      try power.setSleepDisabled(false)
      try store.clear()
      reply(HelperCodec.encode(makeReply(success: true)))
    } catch {
      reply(HelperCodec.encode(makeReply(success: false, message: error.localizedDescription)))
    }
  }

  func prepareForRemoval(withReply reply: @escaping (Data) -> Void) {
    lock.lock()
    defer { lock.unlock() }

    do {
      if record != nil {
        try stopManagedSession(reason: .user)
      }
      try store.clearLastStop()
      try store.removeDirectoryIfEmpty()
      lastStopEvent = nil
      reply(HelperCodec.encode(makeReply(success: true)))
      scheduleCleanExit()
    } catch {
      reply(HelperCodec.encode(makeReply(success: false, message: error.localizedDescription)))
    }
  }

  private func recoverOrResumeSession() {
    lock.lock()
    defer { lock.unlock() }

    do {
      record = try store.load()
    } catch {
      do {
        try power.setSleepDisabled(false)
        try store.clear()
        persistStopEvent(reason: .stateCorrupted)
        record = nil
        scheduleCleanExit()
      } catch {
        // Preserve the corrupt state file as ownership evidence and let launchd
        // restart the helper until normal sleep can be verified and restored.
        scheduleFailureExit()
      }
      return
    }

    guard let record else {
      scheduleCleanExit()
      return
    }

    do {
      if let pendingStopReason = record.pendingStopReason {
        try latchAndStop(reason: pendingStopReason)
        scheduleCleanExit()
        return
      }
      let sleepDisabled = try power.isSleepDisabled()
      lastTemperatureCelsius = power.maximumDieTemperatureCelsius()
      let decision = SessionPolicy.evaluate(
        record: record,
        now: Date(),
        systemUptime: ProcessInfo.processInfo.systemUptime,
        batteryPercent: power.batteryPercent(),
        bootSessionIdentifier: Self.bootSessionIdentifier(),
        sleepDisabled: sleepDisabled,
        thermalState: power.thermalState()
      )
      switch decision {
      case .continueSession:
        if let lastTemperatureCelsius,
          case .stop(let reason) = SessionPolicy.evaluateTemperature(
            temperatureCelsius: lastTemperatureCelsius)
        {
          try latchAndStop(reason: reason)
          scheduleCleanExit()
          return
        }
        try power.beginIdleSleepAssertion()
        startSafetyTimer()
      case .stop(let reason):
        try latchAndStop(reason: reason)
        scheduleCleanExit()
      }
    } catch {
      startSafetyTimer()
      scheduleCleanExit()
    }
  }

  private func enforceSafetyPolicy() {
    guard let record else { return }
    if let pendingStopReason = record.pendingStopReason {
      try? latchAndStop(reason: pendingStopReason)
      return
    }
    guard let sleepDisabled = try? power.isSleepDisabled() else { return }
    let decision = SessionPolicy.evaluate(
      record: record,
      now: Date(),
      systemUptime: ProcessInfo.processInfo.systemUptime,
      batteryPercent: power.batteryPercent(),
      bootSessionIdentifier: Self.bootSessionIdentifier(),
      sleepDisabled: sleepDisabled,
      thermalState: power.thermalState()
    )
    switch decision {
    case .stop(let reason):
      try? latchAndStop(reason: reason)
    case .continueSession:
      let temperature = power.maximumDieTemperatureCelsius()
      lastTemperatureCelsius = temperature
      guard let temperature,
        case .stop(let reason) = SessionPolicy.evaluateTemperature(
          temperatureCelsius: temperature)
      else {
        return
      }
      try? latchAndStop(reason: reason)
    }
  }

  private func latchAndStop(reason: StopReason) throws {
    guard var record else { return }
    let latchedReason = record.pendingStopReason ?? reason
    if record.pendingStopReason == nil {
      record.pendingStopReason = reason
      self.record = record
      try? store.save(record)
    }
    try stopManagedSession(reason: latchedReason)
  }

  private func stopManagedSession(reason: StopReason) throws {
    guard let record else { return }
    try power.setSleepDisabled(record.originalSleepDisabled)
    try store.clear()
    safetyTimer?.cancel()
    safetyTimer = nil
    power.endIdleSleepAssertion()
    self.record = nil
    persistStopEvent(reason: reason)
  }

  private func persistStopEvent(reason: StopReason) {
    let event = StopEvent(reason: reason, stoppedAt: Date())
    lastStopEvent = event
    try? store.saveLastStop(event)
  }

  private func startSafetyTimer() {
    safetyTimer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    timer.schedule(deadline: .now() + 5, repeating: 15)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.lock.lock()
      self.enforceSafetyPolicy()
      let shouldExit = self.record == nil
      self.lock.unlock()
      if shouldExit {
        self.scheduleCleanExit()
      }
    }
    safetyTimer = timer
    timer.resume()
  }

  private func makeReply(success: Bool, message: String? = nil) -> HelperReply {
    let battery = power.batteryPercent()
    let thermalState = power.thermalState()
    guard let sleepDisabled = try? power.isSleepDisabled() else {
      return HelperReply(
        success: false,
        status: HelperStatus(
          ownership: .unknown,
          isActive: record != nil,
          endDate: record?.endDate,
          batteryPercent: battery,
          batteryFloor: record?.batteryFloor,
          lastStopReason: lastStopEvent?.reason.rawValue,
          lastStoppedAt: lastStopEvent?.stoppedAt,
          thermalState: thermalState.rawValue,
          temperatureCelsius: lastTemperatureCelsius
        ),
        message: message ?? "Unable to read the current system sleep setting."
      )
    }
    let ownership = SessionPolicy.ownership(
      sleepDisabled: sleepDisabled,
      hasManagedSession: record != nil
    )

    return HelperReply(
      success: success,
      status: HelperStatus(
        ownership: ownership,
        isActive: ownership == .managed,
        endDate: record?.endDate,
        batteryPercent: battery,
        batteryFloor: record?.batteryFloor,
        lastStopReason: lastStopEvent?.reason.rawValue,
        lastStoppedAt: lastStopEvent?.stoppedAt,
        thermalState: thermalState.rawValue,
        temperatureCelsius: lastTemperatureCelsius
      ),
      message: message
    )
  }

  private func scheduleCleanExit() {
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15) { [weak self] in
      guard let self else { return }
      self.lock.lock()
      let inactive = self.record == nil
      self.lock.unlock()
      if inactive {
        Foundation.exit(EXIT_SUCCESS)
      }
    }
  }

  private func scheduleFailureExit() {
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
      Foundation.exit(EXIT_FAILURE)
    }
  }

  private static func bootSessionIdentifier() -> String {
    if let result = try? CommandRunner.run(
      "/usr/sbin/sysctl",
      arguments: ["-n", "kern.bootsessionuuid"]
    ), result.terminationStatus == 0 {
      return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let bootDate = Date().addingTimeInterval(-ProcessInfo.processInfo.systemUptime)
    return String(Int(bootDate.timeIntervalSince1970 / 60))
  }
}
