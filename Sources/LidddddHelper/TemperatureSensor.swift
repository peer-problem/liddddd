import CoreFoundation
import Darwin
import Foundation

/// Best-effort Apple Silicon die-temperature reader. Undocumented IOHID
/// symbols are resolved at runtime so an unsupported macOS release or Mac
/// model falls back to ProcessInfo.thermalState instead of crashing the helper.
final class TemperatureSensor {
  private typealias HIDObjectRef = UnsafeRawPointer
  private static let temperatureEventType: Int64 = 15
  private let symbols = Symbols()

  func maximumDieTemperatureCelsius() -> Double? {
    guard let symbols else { return nil }
    let matching =
      [
        "PrimaryUsagePage": NSNumber(value: Int32(0xff00)),
        "PrimaryUsage": NSNumber(value: Int32(0x0005)),
      ] as CFDictionary

    guard let client = symbols.createSystemClient(kCFAllocatorDefault) else { return nil }
    defer { Unmanaged<AnyObject>.fromOpaque(client).release() }

    symbols.setMatching(client, matching)
    guard let services = symbols.copyServices(client)?.takeRetainedValue() else { return nil }

    var maximum: Double?
    for index in 0..<CFArrayGetCount(services) {
      guard let rawService = CFArrayGetValueAtIndex(services, index) else { continue }
      let service = HIDObjectRef(rawService)

      guard
        let property = symbols.copyProperty(service, "Product" as CFString)?.takeRetainedValue(),
        let name = property as? String,
        name.localizedCaseInsensitiveContains("tdie"),
        let event = symbols.copyEvent(service, Self.temperatureEventType, 0, 0)
      else {
        continue
      }
      defer { Unmanaged<AnyObject>.fromOpaque(event).release() }

      let temperature = symbols.getFloatValue(event, Self.temperatureEventType << 16)
      guard temperature > 0, temperature < 150 else { continue }
      maximum = max(maximum ?? temperature, temperature)
    }
    return maximum
  }
}

private final class Symbols {
  typealias HIDObjectRef = UnsafeRawPointer
  typealias CreateSystemClient = @convention(c) (CFAllocator?) -> HIDObjectRef?
  typealias SetMatching = @convention(c) (HIDObjectRef, CFDictionary) -> Void
  typealias CopyServices = @convention(c) (HIDObjectRef) -> Unmanaged<CFArray>?
  typealias CopyProperty = @convention(c) (HIDObjectRef, CFString) -> Unmanaged<CFTypeRef>?
  typealias CopyEvent =
    @convention(c) (HIDObjectRef, Int64, Int32, Int64) -> HIDObjectRef?
  typealias GetFloatValue = @convention(c) (HIDObjectRef, Int64) -> Double

  let createSystemClient: CreateSystemClient
  let setMatching: SetMatching
  let copyServices: CopyServices
  let copyProperty: CopyProperty
  let copyEvent: CopyEvent
  let getFloatValue: GetFloatValue

  private let handle: UnsafeMutableRawPointer

  init?() {
    guard
      let handle = dlopen(
        "/System/Library/Frameworks/IOKit.framework/IOKit",
        RTLD_LAZY | RTLD_LOCAL
      )
    else {
      return nil
    }

    func load<T>(_ name: String, as type: T.Type) -> T? {
      guard let address = dlsym(handle, name) else { return nil }
      return unsafeBitCast(address, to: type)
    }

    guard
      let createSystemClient = load(
        "IOHIDEventSystemClientCreate", as: CreateSystemClient.self),
      let setMatching = load("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
      let copyServices = load("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
      let copyProperty = load("IOHIDServiceClientCopyProperty", as: CopyProperty.self),
      let copyEvent = load("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
      let getFloatValue = load("IOHIDEventGetFloatValue", as: GetFloatValue.self)
    else {
      dlclose(handle)
      return nil
    }

    self.handle = handle
    self.createSystemClient = createSystemClient
    self.setMatching = setMatching
    self.copyServices = copyServices
    self.copyProperty = copyProperty
    self.copyEvent = copyEvent
    self.getFloatValue = getFloatValue
  }

  deinit {
    dlclose(handle)
  }
}
