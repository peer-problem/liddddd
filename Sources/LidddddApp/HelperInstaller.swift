import Foundation
import LidddddCore
import ServiceManagement

enum HelperAvailability: Equatable {
  case applicationInstallRequired
  case applicationUpdateRequired
  case installedApplicationAvailable
  case applicationDestinationConflict
  case localHelperInstallRequired
  case localHelperRepairRequired
  case ready
  case approvalRequired
  case unavailable(String)
}

final class HelperInstaller {
  private let service = SMAppService.daemon(plistName: LidddddConstants.helperPlistName)
  private let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
  private let legacyHelperURL = URL(
    fileURLWithPath: "/Library/PrivilegedHelperTools/io.github.leejaywon.liddddd.helper"
  )
  private let legacyPlistURL = URL(
    fileURLWithPath: "/Library/LaunchDaemons/io.github.leejaywon.liddddd.helper.plist"
  )

  func ensureRegistered() -> HelperAvailability {
    guard isRunningFromApplications else { return applicationPlacementRequirement }
    if legacyFilesExist {
      return isLegacyHelperRunning ? .ready : .localHelperRepairRequired
    }
    switch service.status {
    case .enabled:
      return .ready
    case .requiresApproval:
      return .approvalRequired
    // A fresh packaged daemon can report notFound before ServiceManagement has
    // created its background-task record. Registration validates the bundle
    // and moves it to enabled or requiresApproval when the payload is valid.
    case .notRegistered, .notFound:
      do {
        try service.register()
        return availability(for: service.status)
      } catch {
        #if LIDDDDD_ALLOW_ADHOC
          return .localHelperInstallRequired
        #else
          return .unavailable(
            "Sleep control could not be set up: \(error.localizedDescription)")
        #endif
      }
    @unknown default:
      return .unavailable("Liddddd could not check its sleep control.")
    }
  }

  func currentAvailability() -> HelperAvailability {
    guard isRunningFromApplications else { return applicationPlacementRequirement }
    if legacyFilesExist {
      return isLegacyHelperRunning ? .ready : .localHelperRepairRequired
    }
    return availability(for: service.status)
  }

  func installApplication() throws -> URL {
    let sourceURL = Bundle.main.bundleURL.standardizedFileURL
    guard sourceURL.pathExtension == "app" else {
      throw HelperInstallerError.notApplicationBundle
    }

    let destinationURL = applicationsURL.appendingPathComponent("Liddddd.app")
    if FileManager.default.fileExists(atPath: destinationURL.path) {
      guard Bundle(url: destinationURL)?.bundleIdentifier == LidddddConstants.appBundleIdentifier
      else {
        throw HelperInstallerError.foreignApplicationAtDestination(destinationURL)
      }

      let stagingURL = applicationsURL.appendingPathComponent(
        ".Liddddd-update-\(UUID().uuidString).app")
      try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
      do {
        _ = try FileManager.default.replaceItemAt(
          destinationURL,
          withItemAt: stagingURL,
          backupItemName: nil,
          options: [.usingNewMetadataOnly]
        )
      } catch {
        try? FileManager.default.removeItem(at: stagingURL)
        throw error
      }
      return destinationURL
    }

    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    return destinationURL
  }

  func installedApplicationURL() throws -> URL {
    let destinationURL = applicationsURL.appendingPathComponent("Liddddd.app")
    guard FileManager.default.fileExists(atPath: destinationURL.path),
      Bundle(url: destinationURL)?.bundleIdentifier == LidddddConstants.appBundleIdentifier
    else {
      throw HelperInstallerError.installedApplicationUnavailable
    }
    return destinationURL
  }

  func installLocalHelper() throws {
    #if LIDDDDD_ALLOW_ADHOC
      guard isRunningFromApplications else {
        throw HelperInstallerError.applicationNotInstalled
      }
      guard !legacyFilesExist else {
        throw HelperInstallerError.partialOrExistingHelper
      }
      try runLocalHelperManager(action: "install")
    #else
      throw HelperInstallerError.localInstallUnavailable
    #endif
  }

  func repairHelper() throws {
    if legacyFilesExist {
      #if LIDDDDD_ALLOW_ADHOC
        try runLocalHelperManager(action: "repair")
        return
      #else
        throw HelperInstallerError.localInstallUnavailable
      #endif
    }

    if service.status != .notRegistered {
      try service.unregister()
    }
    try service.register()
  }

  func uninstallHelper() throws {
    if legacyFilesExist {
      #if LIDDDDD_ALLOW_ADHOC
        try runLocalHelperManager(action: "uninstall")
        return
      #else
        throw HelperInstallerError.localInstallUnavailable
      #endif
    }

    if service.status != .notRegistered {
      try service.unregister()
    }
  }

  private func runLocalHelperManager(action: String) throws {
    guard ["install", "repair", "uninstall"].contains(action) else {
      throw HelperInstallerError.invalidManagementAction
    }

    guard
      let installerURL = Bundle.main.resourceURL?.appendingPathComponent(
        "manage-local-helper.sh"),
      FileManager.default.isExecutableFile(atPath: installerURL.path)
    else {
      throw HelperInstallerError.localInstallerMissing
    }

    let escapedPath = installerURL.path.replacingOccurrences(of: "\"", with: "\\\"")
    let appleScript =
      "do shell script (quoted form of \"\(escapedPath)\" & \" \" & quoted form of \"\(action)\") with administrator privileges"
    let result = try run("/usr/bin/osascript", arguments: ["-e", appleScript])
    guard result.status == 0 else {
      throw HelperInstallerError.localInstallFailed(result.error)
    }
    guard action == "uninstall" || isLegacyHelperRunning else {
      throw HelperInstallerError.localInstallFailed(
        "Sleep control was installed, but macOS did not start it."
      )
    }
  }

  func openApprovalSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private func availability(for status: SMAppService.Status) -> HelperAvailability {
    switch status {
    case .enabled:
      .ready
    case .requiresApproval:
      .approvalRequired
    case .notRegistered:
      #if LIDDDDD_ALLOW_ADHOC
        .localHelperInstallRequired
      #else
        .unavailable("Sleep control is not set up.")
      #endif
    case .notFound:
      #if LIDDDDD_ALLOW_ADHOC
        .localHelperInstallRequired
      #else
        .unavailable("This copy of Liddddd is missing its sleep control.")
      #endif
    @unknown default:
      .unavailable("Liddddd could not check its sleep control.")
    }
  }

  private var isRunningFromApplications: Bool {
    let appPath = Bundle.main.bundleURL.standardizedFileURL.path
    let expectedPath = applicationsURL.appendingPathComponent("Liddddd.app").path
    return appPath == expectedPath
  }

  private var applicationPlacementRequirement: HelperAvailability {
    let destinationURL = applicationsURL.appendingPathComponent("Liddddd.app")
    guard FileManager.default.fileExists(atPath: destinationURL.path) else {
      return .applicationInstallRequired
    }
    guard Bundle(url: destinationURL)?.bundleIdentifier == LidddddConstants.appBundleIdentifier
    else {
      return .applicationDestinationConflict
    }
    return installedApplicationIsOlder(at: destinationURL)
      ? .applicationUpdateRequired
      : .installedApplicationAvailable
  }

  private func installedApplicationIsOlder(at destinationURL: URL) -> Bool {
    let installed = Bundle(url: destinationURL)?.infoDictionary ?? [:]
    let current = Bundle.main.infoDictionary ?? [:]

    let installedBuild = Int(installed["CFBundleVersion"] as? String ?? "")
    let currentBuild = Int(current["CFBundleVersion"] as? String ?? "")
    if let installedBuild, let currentBuild, installedBuild != currentBuild {
      return installedBuild < currentBuild
    }

    let installedVersion = installed["CFBundleShortVersionString"] as? String ?? "0"
    let currentVersion = current["CFBundleShortVersionString"] as? String ?? "0"
    return installedVersion.compare(currentVersion, options: .numeric) == .orderedAscending
  }

  private var isLegacyHelperRunning: Bool {
    guard FileManager.default.fileExists(atPath: legacyHelperURL.path),
      FileManager.default.fileExists(atPath: legacyPlistURL.path),
      let result = try? run(
        "/bin/launchctl",
        arguments: ["print", "system/\(LidddddConstants.helperIdentifier)"]
      )
    else {
      return false
    }
    return result.status == 0
  }

  private var legacyFilesExist: Bool {
    FileManager.default.fileExists(atPath: legacyHelperURL.path)
      || FileManager.default.fileExists(atPath: legacyPlistURL.path)
  }

  private func run(_ executable: String, arguments: [String]) throws -> CommandResult {
    let process = Process()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()

    let error = String(
      decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return CommandResult(status: process.terminationStatus, error: error)
  }
}

private struct CommandResult {
  let status: Int32
  let error: String
}

enum HelperInstallerError: LocalizedError {
  case notApplicationBundle
  case foreignApplicationAtDestination(URL)
  case applicationNotInstalled
  case partialOrExistingHelper
  case localInstallerMissing
  case localInstallFailed(String)
  case localInstallUnavailable
  case invalidManagementAction
  case installedApplicationUnavailable

  var errorDescription: String? {
    switch self {
    case .notApplicationBundle:
      "Open the packaged Liddddd app to continue."
    case .foreignApplicationAtDestination(let url):
      "Liddddd cannot replace \(url.path) because it belongs to another app."
    case .applicationNotInstalled:
      "Move Liddddd to Applications first."
    case .partialOrExistingHelper:
      "Liddddd's sleep control is incomplete. Remove it, then try again."
    case .localInstallerMissing:
      "Liddddd is missing a setup file. Download a fresh copy."
    case .localInstallFailed(let message):
      message.isEmpty ? "Liddddd could not install its sleep control." : message
    case .localInstallUnavailable:
      "This build cannot install sleep control."
    case .invalidManagementAction:
      "Liddddd cannot perform that setup action."
    case .installedApplicationUnavailable:
      "Liddddd in Applications could not be opened."
    }
  }
}
