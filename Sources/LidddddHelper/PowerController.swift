import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import LidddddCore

final class PowerController {
  private var assertionID: IOPMAssertionID?
  private let temperatureSensor = TemperatureSensor()

  func isSleepDisabled() throws -> Bool {
    let result = try CommandRunner.run("/usr/bin/pmset", arguments: ["-g"])
    guard result.terminationStatus == 0 else {
      throw PowerError.commandFailed(result.standardError)
    }

    return PowerSettingsParser.sleepDisabled(in: result.standardOutput)
  }

  func setSleepDisabled(_ disabled: Bool) throws {
    let result = try CommandRunner.run(
      "/usr/bin/pmset",
      arguments: ["-a", "disablesleep", disabled ? "1" : "0"]
    )
    guard result.terminationStatus == 0 else {
      throw PowerError.commandFailed(result.standardError)
    }
    guard try isSleepDisabled() == disabled else {
      throw PowerError.verificationFailed
    }
  }

  func batteryPercent() -> Int? {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [AnyObject]

    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
          as? [String: Any],
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
        let current = description[kIOPSCurrentCapacityKey] as? Int,
        let maximum = description[kIOPSMaxCapacityKey] as? Int,
        maximum > 0
      else {
        continue
      }
      return Int((Double(current) / Double(maximum) * 100).rounded())
    }
    return nil
  }

  func thermalState() -> SafetyThermalState {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal:
      .nominal
    case .fair:
      .fair
    case .serious:
      .serious
    case .critical:
      .critical
    @unknown default:
      .unknown
    }
  }

  func maximumDieTemperatureCelsius() -> Double? {
    temperatureSensor.maximumDieTemperatureCelsius()
  }

  func beginIdleSleepAssertion() throws {
    guard assertionID == nil else { return }

    var newID: IOPMAssertionID = 0
    let result = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "Liddddd active safety session" as CFString,
      &newID
    )
    guard result == kIOReturnSuccess else {
      throw PowerError.assertionFailed(result)
    }
    assertionID = newID
  }

  func endIdleSleepAssertion() {
    guard let assertionID else { return }
    IOPMAssertionRelease(assertionID)
    self.assertionID = nil
  }
}

enum PowerError: LocalizedError {
  case commandFailed(String)
  case verificationFailed
  case assertionFailed(IOReturn)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let message):
      message.isEmpty ? "The power setting command failed." : message
    case .verificationFailed:
      "macOS did not apply the requested power setting."
    case .assertionFailed(let code):
      "Unable to create the idle-sleep assertion (\(code))."
    }
  }
}
