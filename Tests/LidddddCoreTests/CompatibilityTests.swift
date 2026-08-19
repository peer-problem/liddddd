import Foundation
import LidddddCore
import Testing

@Suite("Stored and XPC model compatibility")
struct CompatibilityTests {
  @Test("legacy session records decode without monotonic deadline")
  func legacySessionRecordDecodes() throws {
    let legacy = LegacySessionRecord(
      startedAt: Date(timeIntervalSince1970: 1_800_000_000),
      endDate: Date(timeIntervalSince1970: 1_800_003_600),
      batteryFloor: 20,
      originalSleepDisabled: false,
      bootSessionIdentifier: "boot-a"
    )

    let decoded = try JSONDecoder().decode(
      SessionRecord.self,
      from: JSONEncoder().encode(legacy)
    )

    #expect(decoded.endSystemUptime == nil)
    #expect(decoded.pendingStopReason == nil)
    #expect(decoded.batteryFloor == 20)
  }

  @Test("legacy helper replies decode as update-required models")
  func legacyHelperReplyDecodes() throws {
    let legacy = LegacyHelperReply(
      success: true,
      status: LegacyHelperStatus(
        ownership: .normal,
        isActive: false,
        endDate: nil,
        batteryPercent: 80,
        batteryFloor: nil,
        lastStopReason: nil
      ),
      message: nil
    )

    let decoded = try HelperCodec.decode(JSONEncoder().encode(legacy))

    #expect(decoded.protocolVersion == nil)
    #expect(decoded.helperVersion == nil)
    #expect(decoded.status.thermalState == nil)
    #expect(decoded.status.temperatureCelsius == nil)
  }
}

private struct LegacySessionRecord: Codable {
  var startedAt: Date
  var endDate: Date
  var batteryFloor: Int
  var originalSleepDisabled: Bool
  var bootSessionIdentifier: String
}

private struct LegacyHelperStatus: Codable {
  var ownership: SleepOwnership
  var isActive: Bool
  var endDate: Date?
  var batteryPercent: Int?
  var batteryFloor: Int?
  var lastStopReason: String?
}

private struct LegacyHelperReply: Codable {
  var success: Bool
  var status: LegacyHelperStatus
  var message: String?
}
