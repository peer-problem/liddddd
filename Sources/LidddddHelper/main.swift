import Foundation
import LidddddCore
import Security

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let service = HelperService()

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    let requirement = Self.clientCodeSigningRequirement()
    connection.setCodeSigningRequirement(requirement)
    connection.exportedInterface = NSXPCInterface(with: LidddddHelperProtocol.self)
    connection.exportedObject = service
    connection.activate()
    return true
  }

  private static func clientCodeSigningRequirement() -> String {
    let appIdentifier = "identifier \"\(LidddddConstants.appBundleIdentifier)\""

    guard let teamIdentifier = currentTeamIdentifier(), !teamIdentifier.isEmpty else {
      #if LIDDDDD_ALLOW_ADHOC
        return appIdentifier
      #else
        // A distributable helper must never trust a client by identifier alone.
        return "identifier \"io.github.leejaywon.liddddd.invalid-untrusted-build\""
      #endif
    }
    return appIdentifier
      + " and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
  }

  private static func currentTeamIdentifier() -> String? {
    guard let executableURL = Bundle.main.executableURL else { return nil }
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &code) == errSecSuccess,
      let code
    else {
      return nil
    }

    var information: CFDictionary?
    guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
      let dictionary = information as? [CFString: Any]
    else {
      return nil
    }
    return dictionary[kSecCodeInfoTeamIdentifier] as? String
  }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: LidddddConstants.helperIdentifier)
listener.delegate = delegate
listener.activate()
RunLoop.current.run()
