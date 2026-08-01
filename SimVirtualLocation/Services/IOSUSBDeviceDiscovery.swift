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
        // `--no-color` is a global option: pymobiledevice3 rejects it after the subcommand.
        let task = try await runner.taskForIOS(args: ["--no-color", "usbmux", "list", "-u"], showAlert: showAlert)

        let exe = task.executableURL?.path ?? ""
        let args = task.arguments?.joined(separator: " ") ?? ""
        log("getConnectedDevices: \(exe) \(args)")

        let result = try ProcessRunner.run(task)

        guard result.terminationStatus == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
            log("device list failed: \(message.isEmpty ? "exit \(result.terminationStatus)" : message)")
            throw IOSUSBDiscoveryError.listCommandFailed
        }

        let devices = try JSONDecoder().decode([Device].self, from: result.stdout)
        log("connected devices: [\(devices.map { "\($0.id) \($0.name) \($0.version)" }.joined(separator: ", "))]")

        return devices
    }
}
