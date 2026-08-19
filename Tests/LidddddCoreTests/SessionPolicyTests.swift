import Foundation
import LidddddCore
import Testing

@Suite("Session safety policy")
struct SessionPolicyTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let uptime: TimeInterval = 1_000

  @Test("valid session continues")
  func validSessionContinues() {
    #expect(evaluate(makeRecord()) == .continueSession)
  }

  @Test("monotonic deadline expires even when wall clock moves backward")
  func monotonicDeadlineWins() {
    let record = makeRecord(
      endDate: now.addingTimeInterval(86_400),
      endSystemUptime: uptime
    )
    #expect(evaluate(record) == .stop(.expired))
  }

  @Test("legacy record falls back to wall-clock deadline")
  func legacyDeadlineFallback() {
    let record = makeRecord(endDate: now, endSystemUptime: nil)
    #expect(evaluate(record) == .stop(.expired))
  }

  @Test("battery floor is inclusive")
  func batteryFloorStops() {
    #expect(evaluate(makeRecord(), batteryPercent: 20) == .stop(.batteryFloor))
  }

  @Test("rebooted session stops")
  func rebootStops() {
    #expect(evaluate(makeRecord(), bootIdentifier: "boot-b") == .stop(.rebooted))
  }

  @Test("missing battery reading stops safely")
  func missingBatteryStops() {
    #expect(evaluate(makeRecord(), batteryPercent: nil) == .stop(.batteryUnavailable))
  }

  @Test("externally changed sleep state stops")
  func sleepStateChangeStops() {
    #expect(evaluate(makeRecord(), sleepDisabled: false) == .stop(.sleepSettingChanged))
  }

  @Test("critical thermal state stops")
  func criticalThermalStateStops() {
    #expect(evaluate(makeRecord(), thermalState: .critical) == .stop(.thermalCritical))
  }

  @Test("serious thermal state stops")
  func seriousThermalStateStops() {
    #expect(evaluate(makeRecord(), thermalState: .serious) == .stop(.thermalSerious))
  }

  @Test("measured temperature limit is inclusive")
  func measuredTemperatureStops() {
    #expect(
      SessionPolicy.evaluateTemperature(temperatureCelsius: 89.9)
        == .continueSession)
    #expect(
      SessionPolicy.evaluateTemperature(temperatureCelsius: 90)
        == .stop(.temperatureLimit))
  }

  @Test("latched stop reason survives a cleared thermal condition")
  func latchedStopReasonWins() {
    let record = makeRecord(pendingStopReason: .temperatureLimit)
    #expect(evaluate(record, thermalState: .nominal) == .stop(.temperatureLimit))
  }

  @Test("limits reject unsafe values and include safe boundaries")
  func validationLimits() throws {
    #expect(throws: PolicyError.invalidDuration) {
      try SessionPolicy.validate(duration: 60, batteryFloor: 20)
    }
    #expect(throws: PolicyError.invalidBatteryFloor) {
      try SessionPolicy.validate(duration: 3_600, batteryFloor: 5)
    }
    try SessionPolicy.validate(duration: 15 * 60, batteryFloor: 10)
    try SessionPolicy.validate(duration: 8 * 60 * 60, batteryFloor: 30)
  }

  @Test("sleep ownership distinguishes external state")
  func ownershipStates() {
    #expect(SessionPolicy.ownership(sleepDisabled: false, hasManagedSession: false) == .normal)
    #expect(SessionPolicy.ownership(sleepDisabled: true, hasManagedSession: true) == .managed)
    #expect(SessionPolicy.ownership(sleepDisabled: true, hasManagedSession: false) == .external)
  }

  @Test("pmset parser reads enabled state")
  func parsesEnabledSleepDisabled() {
    #expect(PowerSettingsParser.sleepDisabled(in: " sleepdisabled  1\n displaysleep 10"))
  }

  @Test("pmset parser reads disabled and absent states")
  func parsesNormalSleepState() {
    #expect(!PowerSettingsParser.sleepDisabled(in: "SleepDisabled 0"))
    #expect(!PowerSettingsParser.sleepDisabled(in: "sleep 1\ndisplaysleep 10"))
  }

  private func evaluate(
    _ record: SessionRecord,
    batteryPercent: Int? = 70,
    bootIdentifier: String = "boot-a",
    sleepDisabled: Bool = true,
    thermalState: SafetyThermalState = .nominal
  ) -> SafetyDecision {
    SessionPolicy.evaluate(
      record: record,
      now: now,
      systemUptime: uptime,
      batteryPercent: batteryPercent,
      bootSessionIdentifier: bootIdentifier,
      sleepDisabled: sleepDisabled,
      thermalState: thermalState
    )
  }

  private func makeRecord(
    endDate: Date? = nil,
    endSystemUptime: TimeInterval? = 4_600,
    pendingStopReason: StopReason? = nil
  ) -> SessionRecord {
    SessionRecord(
      startedAt: now.addingTimeInterval(-60),
      endDate: endDate ?? now.addingTimeInterval(3_600),
      batteryFloor: 20,
      originalSleepDisabled: false,
      bootSessionIdentifier: "boot-a",
      endSystemUptime: endSystemUptime,
      pendingStopReason: pendingStopReason
    )
  }
}
