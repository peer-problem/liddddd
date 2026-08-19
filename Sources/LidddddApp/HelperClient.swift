@preconcurrency import Foundation
import LidddddCore

final class HelperClient: @unchecked Sendable {
  typealias Completion = @MainActor @Sendable (Result<HelperReply, Error>) -> Void

  private final class ConnectionBox: @unchecked Sendable {
    let connection: NSXPCConnection

    init(_ connection: NSXPCConnection) {
      self.connection = connection
    }
  }

  func status(completion: @escaping Completion) {
    request({ proxy, reply in proxy.status(withReply: reply) }, completion: completion)
  }

  func start(
    duration: TimeInterval,
    batteryFloor: Int,
    completion: @escaping Completion
  ) {
    request(
      { proxy, reply in
        proxy.start(
          durationSeconds: duration,
          batteryFloor: batteryFloor,
          withReply: reply
        )
      },
      completion: completion
    )
  }

  func stop(completion: @escaping Completion) {
    request({ proxy, reply in proxy.stop(withReply: reply) }, completion: completion)
  }

  func restoreNormalSleep(completion: @escaping Completion) {
    request({ proxy, reply in proxy.restoreNormalSleep(withReply: reply) }, completion: completion)
  }

  func prepareForRemoval(completion: @escaping Completion) {
    request({ proxy, reply in proxy.prepareForRemoval(withReply: reply) }, completion: completion)
  }

  private func request(
    _ operation: @escaping @Sendable (LidddddHelperProtocol, @escaping (Data) -> Void) -> Void,
    completion: @escaping Completion
  ) {
    let connection = NSXPCConnection(
      machServiceName: LidddddConstants.helperIdentifier,
      options: .privileged
    )
    connection.remoteObjectInterface = NSXPCInterface(with: LidddddHelperProtocol.self)
    connection.activate()
    let connectionBox = ConnectionBox(connection)

    let errorHandler: @Sendable (Error) -> Void = { error in
      connectionBox.connection.invalidate()
      Task { @MainActor in completion(.failure(error)) }
    }

    guard
      let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler)
        as? LidddddHelperProtocol
    else {
      connection.invalidate()
      Task { @MainActor in
        completion(.failure(HelperClientError.invalidProxy))
      }
      return
    }

    operation(proxy) { data in
      connectionBox.connection.invalidate()
      let result = Result { try HelperCodec.decode(data) }
      Task { @MainActor in completion(result) }
    }
  }
}

enum HelperClientError: LocalizedError {
  case invalidProxy

  var errorDescription: String? {
    "Liddddd could not reach its sleep control."
  }
}
