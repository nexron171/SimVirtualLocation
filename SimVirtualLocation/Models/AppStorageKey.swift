import Foundation

/// Centralized `UserDefaults` keys (keep legacy string values for migration).
enum AppStorageKey {
    static let savedLocations = "saved_locations"
    static let xcodePath = "xcode_path"
    /// Legacy name — stores `AppPlatform.rawValue`.
    static let platform = "device_type"
    static let adbPath = "adb_path"
    static let adbDeviceId = "adb_device_id"
    static let isEmulator = "is_emulator"
    static let useUserspace = "use_userspace_tunnel"
}
