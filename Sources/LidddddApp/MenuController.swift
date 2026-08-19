import AppKit
import Foundation
import LidddddCore

@MainActor
final class MenuController: NSObject, NSMenuDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let menu = NSMenu()
  private let helperClient: HelperClient
  private let helperInstaller: HelperInstaller
  private var helperAvailability: HelperAvailability
  private(set) var currentStatus: HelperStatus?
  private var lastError: String?
  private var helperUpdateMessage: String?
  private var installedHelperVersion: String?
  private var confirmingHelperRemoval = false
  private var isMenuOpen = false

  private var selectedDuration: TimeInterval {
    get { AppPreferences.duration }
    set { AppPreferences.duration = newValue }
  }

  private var selectedBatteryFloor: Int {
    get { AppPreferences.batteryFloor }
    set { AppPreferences.batteryFloor = newValue }
  }

  init(helperClient: HelperClient, helperInstaller: HelperInstaller) {
    self.helperClient = helperClient
    self.helperInstaller = helperInstaller
    self.helperAvailability = helperInstaller.ensureRegistered()
    super.init()

    menu.delegate = self
    statusItem.menu = menu
    statusItem.isVisible = true
    statusItem.button?.toolTip = "Liddddd"
    statusItem.button?.imagePosition = .imageOnly
    statusItem.button?.imageScaling = .scaleProportionallyDown
    rebuildMenu()

    if helperAvailability == .ready {
      refreshStatus()
    }
  }

  func menuWillOpen(_ menu: NSMenu) {
    isMenuOpen = true
    refreshAvailability()
  }

  func menuDidClose(_ menu: NSMenu) {
    isMenuOpen = false
  }

  func refreshAvailability() {
    helperAvailability = helperInstaller.currentAvailability()
    if helperAvailability == .ready {
      refreshStatus()
    } else {
      rebuildMenu()
    }
  }

  func showMenu() {
    guard !isMenuOpen else { return }
    statusItem.button?.performClick(nil)
  }

  func stopForTermination(completion: @escaping @MainActor (Bool) -> Void) {
    guard currentStatus?.isActive == true else {
      completion(true)
      return
    }
    helperClient.stop { result in
      switch result {
      case .success(let reply):
        completion(reply.success)
      case .failure:
        completion(false)
      }
    }
  }

  func refreshStatus() {
    helperClient.status { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let reply):
        self.currentStatus = reply.status
        self.installedHelperVersion = reply.helperVersion
        if reply.protocolVersion != LidddddConstants.protocolVersion
          || reply.helperVersion != LidddddConstants.helperVersion
        {
          self.helperUpdateMessage = "Liddddd needs to update its sleep control."
          self.lastError = nil
        } else {
          self.helperUpdateMessage = nil
          self.lastError = reply.success ? nil : reply.message
        }
      case .failure(let error):
        self.lastError = error.localizedDescription
      }
      self.rebuildMenu()
    }
  }

  private func rebuildMenu() {
    menu.removeAllItems()
    defer { updateStatusItemAppearance() }

    if confirmingHelperRemoval {
      buildHelperRemovalConfirmation()
      menu.addItem(.separator())
      menu.addItem(informationMenuItem())
      menu.addItem(.separator())
      addAction(currentStatus?.isActive == true ? "Quit and Stop" : "Quit", action: #selector(quit))
      return
    }

    switch helperAvailability {
    case .applicationInstallRequired:
      addAction(
        "Move the App to Applications and Open",
        action: #selector(installApplication)
      )
    case .applicationUpdateRequired:
      addAction("Update and Open…", action: #selector(installApplication))
    case .installedApplicationAvailable:
      addHeader("Liddddd Is Already Installed")
      addStatus("Open the copy in Applications.")
      menu.addItem(.separator())
      addAction("Open Liddddd", action: #selector(openInstalledApplication))
    case .applicationDestinationConflict:
      addHeader("Liddddd Cannot Be Installed")
      addStatus("Remove or rename /Applications/Liddddd.app, then try again.", warning: true)
    case .localHelperInstallRequired:
      addHeader("Allow Liddddd to Control Sleep")
      addStatus("macOS will ask for an administrator password.")
      menu.addItem(.separator())
      addAction("Continue…", action: #selector(installLocalHelper))
    case .localHelperRepairRequired:
      addHeader("Liddddd Needs Repair")
      addStatus("Its sleep control is missing or not running.", warning: true)
      menu.addItem(.separator())
      addAction("Repair…", action: #selector(repairSystemHelper))
      addAction("Remove Sleep Control…", action: #selector(requestRemoveSystemHelper))
    case .ready:
      if let helperUpdateMessage {
        buildHelperUpdateMenu(message: helperUpdateMessage)
      } else {
        buildReadyMenu()
      }
    case .approvalRequired:
      addHeader("Allow Liddddd to Control Sleep")
      addStatus("Turn on its background item in System Settings.")
      menu.addItem(.separator())
      addAction("Open System Settings…", action: #selector(openApprovalSettings))
    case .unavailable(let message):
      addHeader("Liddddd Cannot Start")
      addStatus(message, warning: true)
      menu.addItem(.separator())
      addAction("Try Setup Again", action: #selector(retryHelperSetup))
    }

    if let lastError {
      menu.addItem(.separator())
      addStatus(lastError, warning: true)
    }
    menu.addItem(.separator())
    menu.addItem(informationMenuItem())
    menu.addItem(.separator())
    addAction(currentStatus?.isActive == true ? "Quit and Stop" : "Quit", action: #selector(quit))
  }

  private func buildReadyMenu() {
    guard let status = currentStatus else {
      addHeader("Liddddd")
      addStatus("Loading…")
      return
    }

    switch status.ownership {
    case .normal:
      addAction("Liddddd: Off — Start", action: #selector(startSession))
      menu.addItem(.separator())
      menu.addItem(durationMenuItem())
      menu.addItem(batteryFloorMenuItem())
      addStatus("Stops automatically if your Mac gets too hot")
      if let reason = status.lastStopReason {
        menu.addItem(.separator())
        addStatus("Last stopped: \(stopReasonText(reason))")
      }
      menu.addItem(.separator())
      menu.addItem(systemHelperMenuItem())
    case .managed:
      addAction("Liddddd: On — Stop", action: #selector(stopSession))
      if let endDate = status.endDate {
        addStatus("Time left: \(remainingTime(until: endDate))")
      }
      if let battery = status.batteryPercent, let floor = status.batteryFloor {
        addStatus("Battery: \(battery)% · stops at \(floor)%")
      }
      if let temperature = status.temperatureCelsius {
        addStatus(
          String(
            format: "Temperature: %.1f°C · stops at %.0f°C",
            temperature,
            LidddddConstants.temperatureCutoffCelsius
          ),
          warning: temperature >= LidddddConstants.temperatureCutoffCelsius - 5
        )
      } else {
        addStatus("Temperature unavailable · stops if your Mac gets too hot")
      }
      addStatus("Keep your Mac uncovered while Liddddd is on.", warning: true)
    case .external:
      addHeader("Liddddd Cannot Start")
      addStatus("Another app or command already turned off Mac sleep.", warning: true)
      addStatus("Time, battery, and heat limits are not active.")
      menu.addItem(.separator())
      addAction("Turn Mac Sleep Back On…", action: #selector(restoreNormalSleep))
    case .unknown:
      addHeader("Liddddd Cannot Check Mac Sleep")
      addStatus("Check the sleep setting before starting.", warning: true)
      menu.addItem(.separator())
      addAction("Check Again", action: #selector(retryStatus))
    }
  }

  private func buildHelperUpdateMenu(message: String) {
    addHeader("Liddddd Needs an Update")
    addStatus(message, warning: true)
    addStatus("Any active session will stop first.")
    menu.addItem(.separator())
    addAction("Update Sleep Control…", action: #selector(repairSystemHelper))
    addAction("Remove Sleep Control…", action: #selector(requestRemoveSystemHelper))
  }

  private func buildHelperRemovalConfirmation() {
    addHeader("Remove Sleep Control?")
    addStatus("Liddddd will stop first and normal Mac sleep will return.", warning: true)
    menu.addItem(.separator())
    addAction("Remove", action: #selector(confirmRemoveSystemHelper))
    addAction("Cancel", action: #selector(cancelRemoveSystemHelper))
  }

  private func durationMenuItem() -> NSMenuItem {
    let item = NSMenuItem(title: "Stop after", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "Stop after")
    let choices = [
      (15, "15 minutes"), (30, "30 minutes"), (60, "1 hour"),
      (120, "2 hours"), (240, "4 hours"), (480, "8 hours"),
    ]
    for (minutes, title) in choices {
      let choice = NSMenuItem(
        title: title,
        action: #selector(selectDuration(_:)),
        keyEquivalent: ""
      )
      choice.target = self
      choice.tag = minutes
      choice.state = selectedDuration == TimeInterval(minutes * 60) ? .on : .off
      submenu.addItem(choice)
    }
    item.submenu = submenu
    item.title = "Stop after: \(durationText(selectedDuration))"
    return item
  }

  private func systemHelperMenuItem() -> NSMenuItem {
    let item = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "Advanced")
    let version = NSMenuItem(
      title: "Sleep control: \(installedHelperVersion ?? LidddddConstants.helperVersion)",
      action: nil,
      keyEquivalent: ""
    )
    version.isEnabled = false
    submenu.addItem(version)
    submenu.addItem(.separator())
    let remove = NSMenuItem(
      title: "Remove Sleep Control…",
      action: #selector(requestRemoveSystemHelper),
      keyEquivalent: ""
    )
    remove.target = self
    submenu.addItem(remove)
    item.submenu = submenu
    return item
  }

  private func informationMenuItem() -> NSMenuItem {
    let item = NSMenuItem(title: LidddddConstants.productName, action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: LidddddConstants.productName)

    let about = NSMenuItem(
      title: "About Liddddd",
      action: #selector(showAbout),
      keyEquivalent: ""
    )
    about.target = self
    submenu.addItem(about)

    let repository = NSMenuItem(
      title: "View on GitHub",
      action: #selector(openRepository),
      keyEquivalent: ""
    )
    repository.target = self
    submenu.addItem(repository)

    item.submenu = submenu
    return item
  }

  private func batteryFloorMenuItem() -> NSMenuItem {
    let item = NSMenuItem(title: "Stop at battery", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "Stop at battery")
    for percent in [10, 20, 30] {
      let choice = NSMenuItem(
        title: "\(percent)%",
        action: #selector(selectBatteryFloor(_:)),
        keyEquivalent: ""
      )
      choice.target = self
      choice.tag = percent
      choice.state = selectedBatteryFloor == percent ? .on : .off
      submenu.addItem(choice)
    }
    item.submenu = submenu
    item.title = "Stop at battery: \(selectedBatteryFloor)%"
    return item
  }

  private func addHeader(_ title: String) {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    menu.addItem(item)
  }

  private func addStatus(_ title: String, warning: Bool = false) {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    if warning {
      item.attributedTitle = NSAttributedString(
        string: title,
        attributes: [.foregroundColor: NSColor.systemOrange]
      )
    }
    menu.addItem(item)
  }

  private func addAction(_ title: String, action: Selector) {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
  }

  private func remainingTime(until endDate: Date) -> String {
    let seconds = max(0, Int(endDate.timeIntervalSinceNow))
    return String(format: "%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60)
  }

  private func durationText(_ duration: TimeInterval) -> String {
    let minutes = Int(duration / 60)
    if minutes < 60 { return "\(minutes) minutes" }
    let hours = minutes / 60
    return "\(hours) hour\(hours == 1 ? "" : "s")"
  }

  private func stopReasonText(_ reason: String) -> String {
    switch reason {
    case "user": "By you"
    case "expired": "Time limit reached"
    case "batteryFloor": "Battery reached the limit"
    case "batteryUnavailable": "Battery level could not be checked"
    case "rebooted": "Mac restarted"
    case "sleepSettingChanged": "Mac sleep setting changed"
    case "thermalSerious": "Mac was getting too hot"
    case "thermalCritical": "Mac was overheating"
    case "temperatureLimit": "Mac reached 90°C"
    case "stateCorrupted": "Saved session needed repair"
    default: reason
    }
  }

  private func updateStatusItemAppearance() {
    let state: MenuBarIconState
    let tooltip: String

    if lastError != nil || helperUpdateMessage != nil || helperAvailability != .ready {
      state = .attention
      tooltip = "Liddddd needs attention"
    } else if currentStatus?.isActive == true {
      state = .on
      tooltip = "Liddddd is on"
    } else {
      state = .off
      tooltip = "Liddddd is off"
    }

    statusItem.button?.image = MenuBarIcon.image(for: state)
    statusItem.button?.toolTip = tooltip
  }

  @objc private func selectDuration(_ sender: NSMenuItem) {
    selectedDuration = TimeInterval(sender.tag * 60)
    rebuildMenu()
  }

  @objc private func selectBatteryFloor(_ sender: NSMenuItem) {
    selectedBatteryFloor = sender.tag
    rebuildMenu()
  }

  @objc private func startSession() {
    lastError = nil
    helperClient.start(
      duration: selectedDuration,
      batteryFloor: selectedBatteryFloor
    ) {
      [weak self] result in
      self?.apply(result)
    }
  }

  @objc private func stopSession() {
    lastError = nil
    helperClient.stop { [weak self] result in self?.apply(result) }
  }

  @objc private func restoreNormalSleep() {
    lastError = nil
    helperClient.restoreNormalSleep { [weak self] result in self?.apply(result) }
  }

  @objc private func installApplication() {
    lastError = nil
    do {
      let destinationURL = try helperInstaller.installApplication()
      relaunchInstalledApplication(at: destinationURL)
    } catch {
      showErrorInMenu(error.localizedDescription)
    }
  }

  @objc private func openInstalledApplication() {
    do {
      relaunchInstalledApplication(at: try helperInstaller.installedApplicationURL())
    } catch {
      showErrorInMenu(error.localizedDescription)
    }
  }

  private func relaunchInstalledApplication(at url: URL) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) {
      [weak self] application, error in
      Task { @MainActor in
        if let error {
          self?.showErrorInMenu(error.localizedDescription)
        } else if application == nil {
          self?.showErrorInMenu("macOS did not launch the installed Liddddd app.")
        } else {
          NSApp.terminate(nil)
        }
      }
    }
  }

  private func showErrorInMenu(_ message: String) {
    lastError = message
    rebuildMenu()
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(150))
      self?.showMenu()
    }
  }

  @objc private func installLocalHelper() {
    lastError = nil
    do {
      try helperInstaller.installLocalHelper()
      helperAvailability = helperInstaller.currentAvailability()
      if helperAvailability == .ready {
        refreshStatus()
      } else {
        rebuildMenu()
      }
    } catch {
      lastError = error.localizedDescription
      rebuildMenu()
    }
  }

  @objc private func repairSystemHelper() {
    performAfterStoppingIfNeeded { [weak self] in
      guard let self else { return }
      do {
        try self.helperInstaller.repairHelper()
        self.helperUpdateMessage = nil
        self.helperAvailability = self.helperInstaller.ensureRegistered()
        self.refreshAvailability()
      } catch {
        self.lastError = error.localizedDescription
        self.rebuildMenu()
      }
    }
  }

  @objc private func requestRemoveSystemHelper() {
    confirmingHelperRemoval = true
    rebuildMenu()
  }

  @objc private func cancelRemoveSystemHelper() {
    confirmingHelperRemoval = false
    rebuildMenu()
  }

  @objc private func confirmRemoveSystemHelper() {
    confirmingHelperRemoval = false
    if helperAvailability == .ready, helperUpdateMessage == nil {
      helperClient.prepareForRemoval { [weak self] result in
        guard let self else { return }
        switch result {
        case .success(let reply) where reply.success:
          self.finishHelperRemoval()
        case .success(let reply):
          self.lastError = reply.message ?? "Sleep control could not be removed."
          self.rebuildMenu()
        case .failure(let error):
          self.lastError = error.localizedDescription
          self.rebuildMenu()
        }
      }
      return
    }

    performAfterStoppingIfNeeded { [weak self] in
      self?.finishHelperRemoval()
    }
  }

  private func finishHelperRemoval() {
    do {
      try helperInstaller.uninstallHelper()
      NSApp.terminate(nil)
    } catch {
      lastError = error.localizedDescription
      rebuildMenu()
    }
  }

  private func performAfterStoppingIfNeeded(_ operation: @escaping @MainActor () -> Void) {
    guard currentStatus?.isActive == true else {
      operation()
      return
    }
    helperClient.stop { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let reply) where reply.success:
        self.currentStatus = reply.status
        operation()
      case .success(let reply):
        self.lastError = reply.message ?? "The active session could not be stopped."
        self.rebuildMenu()
      case .failure(let error):
        self.lastError = error.localizedDescription
        self.rebuildMenu()
      }
    }
  }

  @objc private func openApprovalSettings() {
    helperInstaller.openApprovalSettings()
  }

  @objc private func retryHelperSetup() {
    helperAvailability = helperInstaller.ensureRegistered()
    rebuildMenu()
    if helperAvailability == .ready { refreshStatus() }
  }

  @objc private func retryStatus() {
    lastError = nil
    refreshStatus()
  }

  @objc private func showAbout() {
    NSApp.orderFrontStandardAboutPanel(
      options: [
        .applicationName: LidddddConstants.productName,
        .credits: NSAttributedString(
          string: "A small, open-source macOS utility for controlled lid-closed operation."
        ),
      ]
    )
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openRepository() {
    NSWorkspace.shared.open(LidddddConstants.repositoryURL)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func apply(_ result: Result<HelperReply, Error>) {
    switch result {
    case .success(let reply):
      currentStatus = reply.status
      lastError = reply.success ? nil : reply.message
    case .failure(let error):
      lastError = error.localizedDescription
    }
    rebuildMenu()
  }

}
