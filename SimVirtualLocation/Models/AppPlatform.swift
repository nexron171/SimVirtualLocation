import Foundation

/// Primary platform for location injection (persisted under `AppStorageKey.platform`).
enum AppPlatform: Int, CaseIterable, Identifiable {
    case iOS = 0
    case android = 1

    var id: Int { rawValue }
}
