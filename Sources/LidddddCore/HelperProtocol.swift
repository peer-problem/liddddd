import Foundation

@objc public protocol LidddddHelperProtocol {
  func status(withReply reply: @escaping (Data) -> Void)
  func start(
    durationSeconds: Double,
    batteryFloor: Int,
    withReply reply: @escaping (Data) -> Void
  )
  func stop(withReply reply: @escaping (Data) -> Void)
  func restoreNormalSleep(withReply reply: @escaping (Data) -> Void)
  func prepareForRemoval(withReply reply: @escaping (Data) -> Void)
}
