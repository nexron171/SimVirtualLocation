import Foundation

enum IOSUSBDiscoveryError: Error {
    case listCommandFailed
}

/// Reads connected iOS devices via `pymobiledevice3 usbmux list` (uses the same JSON shape as before).
enum IOSUSBDeviceDiscovery {
    static func fetchConnectedDevices(
        runner: IOSProcessLaunching,
        showAlert: @escaping (String) -> Void,
        log: @escaping (String) -> Void
    ) async throws -> [Device] {
        let task = try await runner.taskForIOS(args: ["usbmux", "list", "--no-color", "-u"], showAlert: showAlert)

        let exe = task.executableURL?.path ?? ""
        let args = task.arguments?.joined(separator: " ") ?? ""
        log("getConnectedDevices: \(exe) \(args)")

        let result = try ProcessRunner.run(task)

        guard result.terminationStatus == 0 else {
            throw IOSUSBDiscoveryError.listCommandFailed
        }

        let devices = try JSONDecoder().decode([Device].self, from: result.stdout)
        log("connected devices: [\(devices.map { "\($0.id) \($0.name) \($0.version)" }.joined(separator: ", "))]")

        return devices
    }
}
