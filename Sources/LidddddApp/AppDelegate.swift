import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var menuController: MenuController?
  private var waitingForTerminationReply = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)

    let installer = HelperInstaller()
    let helperClient = HelperClient()
    let menuController = MenuController(
      helperClient: helperClient,
      helperInstaller: installer
    )
    self.menuController = menuController

    // Wait for AppKit to place the status item before using it as the menu anchor.
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) {
      menuController.showMenu()
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    menuController?.refreshAvailability()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    menuController?.showMenu()
    return true
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !waitingForTerminationReply else { return .terminateLater }
    guard menuController?.currentStatus?.isActive == true else { return .terminateNow }

    waitingForTerminationReply = true
    menuController?.stopForTermination { [weak self] success in
      self?.waitingForTerminationReply = false
      sender.reply(toApplicationShouldTerminate: success)
    }
    return .terminateLater
  }
}
