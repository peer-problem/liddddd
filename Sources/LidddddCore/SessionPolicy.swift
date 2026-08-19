import Foundation

public struct SessionRecord: Codable, Equatable, Sendable {
  public var startedAt: Date
  public var endDate: Date
  public var batteryFloor: Int
  public var originalSleepDisabled: Bool
  public var bootSessionIdentifier: String
  public var endSystemUptime: TimeInterval?
  public var pendingStopReason: StopReason?

  public init(
    startedAt: Date,
    endDate: Date,
    batteryFloor: Int,
    originalSleepDisabled: Bool,
    bootSessionIdentifier: String,
    endSystemUptime: TimeInterval? = nil,
    pendingStopReason: StopReason? = nil
  ) {
    self.startedAt = startedAt
    self.endDate = endDate
    self.batteryFloor = batteryFloor
    self.originalSleepDisabled = originalSleepDisabled
    self.bootSessionIdentifier = bootSessionIdentifier
    self.endSystemUptime = endSystemUptime
    self.pendingStopReason = pendingStopReason
  }
}

public struct StopEvent: Codable, Equatable, Sendable {
  public var reason: StopReason
  public var stoppedAt: Date

  public init(reason: StopReason, stoppedAt: Date) {
    self.reason = reason
    self.stoppedAt = stoppedAt
  }
}

public enum SafetyThermalState: String, Codable, Equatable, Sendable {
  case nominal
  case fair
  case serious
  case critical
  case unknown
}

public enum StopReason: String, Codable, Equatable, Sendable {
  case user
  case expired
  case batteryFloor
  case batteryUnavailable
  case rebooted
  case sleepSettingChanged
  case thermalSerious
  case thermalCritical
  case temperatureLimit
  case stateCorrupted
}

public enum SafetyDecision: Equatable, Sendable {
  case continueSession
  case stop(StopReason)
}

public enum SessionPolicy {
  public static func ownership(
    sleepDisabled: Bool,
    hasManagedSession: Bool
  ) -> SleepOwnership {
    if sleepDisabled, hasManagedSession {
      return .managed
    }
    if sleepDisabled {
      return .external
    }
    return .normal
  }

  public static func validate(duration: TimeInterval, batteryFloor: Int) throws {
    guard duration >= LidddddConstants.minimumDuration,
      duration <= LidddddConstants.maximumDuration
    else {
      throw PolicyError.invalidDuration
    }

    guard batteryFloor >= LidddddConstants.minimumBatteryFloor,
      batteryFloor <= LidddddConstants.maximumBatteryFloor
    else {
      throw PolicyError.invalidBatteryFloor
    }

  }

  public static func evaluate(
    record: SessionRecord,
    now: Date,
    systemUptime: TimeInterval,
    batteryPercent: Int?,
    bootSessionIdentifier: String,
    sleepDisabled: Bool,
    thermalState: SafetyThermalState
  ) -> SafetyDecision {
    if let pendingStopReason = record.pendingStopReason {
      return .stop(pendingStopReason)
    }
    guard record.bootSessionIdentifier == bootSessionIdentifier else {
      return .stop(.rebooted)
    }
    guard sleepDisabled else {
      return .stop(.sleepSettingChanged)
    }
    let hasTimeRemaining: Bool
    if let endSystemUptime = record.endSystemUptime {
      hasTimeRemaining = systemUptime < endSystemUptime
    } else {
      hasTimeRemaining = now < record.endDate
    }
    guard hasTimeRemaining else {
      return .stop(.expired)
    }
    guard let batteryPercent else {
      return .stop(.batteryUnavailable)
    }
    if batteryPercent <= record.batteryFloor {
      return .stop(.batteryFloor)
    }
    if thermalState == .critical {
      return .stop(.thermalCritical)
    }
    if thermalState == .serious {
      return .stop(.thermalSerious)
    }
    return .continueSession
  }

  public static func evaluateTemperature(temperatureCelsius: Double) -> SafetyDecision {
    temperatureCelsius >= LidddddConstants.temperatureCutoffCelsius
      ? .stop(.temperatureLimit) : .continueSession
  }
}

public enum PolicyError: LocalizedError, Equatable {
  case invalidDuration
  case invalidBatteryFloor

  public var errorDescription: String? {
    switch self {
    case .invalidDuration:
      "Duration must be between 15 minutes and 8 hours."
    case .invalidBatteryFloor:
      "Battery floor must be between 10% and 30%."
    }
  }
}
