import Foundation

struct CommandResult: Sendable {
  let terminationStatus: Int32
  let standardOutput: String
  let standardError: String
}

enum CommandRunner {
  static func run(_ executable: String, arguments: [String]) throws -> CommandResult {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let error = errorPipe.fileHandleForReading.readDataToEndOfFile()

    return CommandResult(
      terminationStatus: process.terminationStatus,
      standardOutput: String(decoding: output, as: UTF8.self),
      standardError: String(decoding: error, as: UTF8.self)
    )
  }
}
