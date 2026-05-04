import Foundation

/// Minimal surface for building `pymobiledevice3` child processes (e.g. device listing, mount).
protocol IOSProcessLaunching: AnyObject {
    func taskForIOS(args: [String], showAlert: @escaping (String) -> Void) async throws -> Process
}

extension Runner: IOSProcessLaunching {}
