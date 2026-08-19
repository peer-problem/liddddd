import Foundation

public enum SleepOwnership: String, Codable, Sendable {
  case normal
  case managed
  case external
  case unknown
}

public struct HelperStatus: Codable, Equatable, Sendable {
  public var ownership: SleepOwnership
  public var isActive: Bool
  public var endDate: Date?
  public var batteryPercent: Int?
  public var batteryFloor: Int?
  public var lastStopReason: String?
  public var lastStoppedAt: Date?
  public var thermalState: String?
  public var temperatureCelsius: Double?

  public init(
    ownership: SleepOwnership,
    isActive: Bool,
    endDate: Date? = nil,
    batteryPercent: Int? = nil,
    batteryFloor: Int? = nil,
    lastStopReason: String? = nil,
    lastStoppedAt: Date? = nil,
    thermalState: String? = nil,
    temperatureCelsius: Double? = nil
  ) {
    self.ownership = ownership
    self.isActive = isActive
    self.endDate = endDate
    self.batteryPercent = batteryPercent
    self.batteryFloor = batteryFloor
    self.lastStopReason = lastStopReason
    self.lastStoppedAt = lastStoppedAt
    self.thermalState = thermalState
    self.temperatureCelsius = temperatureCelsius
  }
}

public struct HelperReply: Codable, Sendable {
  public var success: Bool
  public var status: HelperStatus
  public var message: String?
  public var protocolVersion: Int?
  public var helperVersion: String?

  public init(
    success: Bool,
    status: HelperStatus,
    message: String? = nil,
    protocolVersion: Int? = LidddddConstants.protocolVersion,
    helperVersion: String? = LidddddConstants.helperVersion
  ) {
    self.success = success
    self.status = status
    self.message = message
    self.protocolVersion = protocolVersion
    self.helperVersion = helperVersion
  }
}

public enum HelperCodec {
  public static func encode(_ reply: HelperReply) -> Data {
    (try? JSONEncoder().encode(reply)) ?? Data()
  }

  public static func decode(_ data: Data) throws -> HelperReply {
    try JSONDecoder().decode(HelperReply.self, from: data)
  }
}
