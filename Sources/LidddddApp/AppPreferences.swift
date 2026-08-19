import Foundation

enum AppPreferences {
  private enum Key {
    static let duration = "selectedDuration"
    static let batteryFloor = "selectedBatteryFloor"
  }

  static var duration: TimeInterval {
    get {
      let stored = UserDefaults.standard.double(forKey: Key.duration)
      return stored == 0 ? 4 * 60 * 60 : stored
    }
    set { UserDefaults.standard.set(newValue, forKey: Key.duration) }
  }

  static var batteryFloor: Int {
    get {
      let stored = UserDefaults.standard.integer(forKey: Key.batteryFloor)
      return stored == 0 ? 20 : stored
    }
    set { UserDefaults.standard.set(newValue, forKey: Key.batteryFloor) }
  }
}
