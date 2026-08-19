import Foundation
import LidddddCore

struct SessionStore {
  static let defaultDirectory = URL(
    fileURLWithPath: "/Library/Application Support/Liddddd",
    isDirectory: true
  )

  private let directory: URL
  private var stateURL: URL { directory.appendingPathComponent("active-session.json") }
  private var lastStopURL: URL { directory.appendingPathComponent("last-stop.json") }

  init(directory: URL = Self.defaultDirectory) {
    self.directory = directory
  }

  func load() throws -> SessionRecord? {
    guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
    return try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: stateURL))
  }

  func save(_ record: SessionRecord) throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o755]
    )
    let data = try JSONEncoder().encode(record)
    try data.write(to: stateURL, options: [.atomic])
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
  }

  func clear() throws {
    guard FileManager.default.fileExists(atPath: stateURL.path) else { return }
    try FileManager.default.removeItem(at: stateURL)
  }

  func loadLastStop() throws -> StopEvent? {
    guard FileManager.default.fileExists(atPath: lastStopURL.path) else { return nil }
    return try JSONDecoder().decode(StopEvent.self, from: Data(contentsOf: lastStopURL))
  }

  func saveLastStop(_ event: StopEvent) throws {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o755]
    )
    let data = try JSONEncoder().encode(event)
    try data.write(to: lastStopURL, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: lastStopURL.path)
  }

  func clearLastStop() throws {
    guard FileManager.default.fileExists(atPath: lastStopURL.path) else { return }
    try FileManager.default.removeItem(at: lastStopURL)
  }

  func removeDirectoryIfEmpty() throws {
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    if contents.isEmpty {
      try FileManager.default.removeItem(at: directory)
    }
  }
}
