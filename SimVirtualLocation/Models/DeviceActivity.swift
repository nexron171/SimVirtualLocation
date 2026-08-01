import Foundation

/// Progress of a device operation, surfaced in the UI.
enum DeviceActivity: Equatable {
    case idle
    case working(String)
    case active(String)
    case failed(String)
}
