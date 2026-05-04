import Foundation

enum SimulatorFetchError: Error, CustomStringConvertible {
    case simctlFailed
    case failedToReadOutput
    case noBootedSimulators
    case noMatchingSimulators(name: String)
    case noMatchingUDID(udid: UUID)

    var description: String {
        switch self {
        case .simctlFailed:
            return "Running `simctl list` failed"
        case .failedToReadOutput:
            return "Failed to read output from simctl"
        case .noBootedSimulators:
            return "No simulators are currently booted"
        case .noMatchingSimulators(let name):
            return "No booted simulators named '\(name)'"
        case .noMatchingUDID(let udid):
            return "No booted simulators with udid: \(udid.uuidString)"
        }
    }
}

enum SimulatorDiscovery {

    /// Lists booted simulators (prefixed with “To all simulators” empty entry). Throws on parse or tool failure.
    static func fetchBootedSimulators(log: @escaping (String) -> Void) throws -> [Simulator] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        // Only booted devices (same as `simctl list devices | grep Booted`, but stable JSON).
        task.arguments = ["simctl", "list", "devices", "booted", "-j"]
        task.environment = ProcessInfo.processInfo.environment
        if let nullIn = FileHandle(forReadingAtPath: "/dev/null") {
            task.standardInput = nullIn
        }

        let exe = task.executableURL?.path ?? "xcrun"
        let args = task.arguments?.joined(separator: " ") ?? ""
        log("getBootedSimulators: \(exe) \(args)")

        let result = try ProcessRunner.run(task)

        guard result.terminationStatus == 0 else {
            let err = String(data: result.stderr, encoding: .utf8) ?? ""
            log("simctl failed (status \(result.terminationStatus)): \(err)")
            throw SimulatorFetchError.simctlFailed
        }

        let bootedSimulators: [Simulator]
        do {
            bootedSimulators = try JSONDecoder().decode(Simulators.self, from: result.stdout).bootedSimulators
        } catch {
            let preview = String(data: result.stdout.prefix(800), encoding: .utf8) ?? ""
            let errText = String(data: result.stderr, encoding: .utf8) ?? ""
            log("simctl JSON decode failed: \(error). stderr: \(errText). stdout prefix: \(preview)")
            throw SimulatorFetchError.failedToReadOutput
        }

        if bootedSimulators.isEmpty {
            throw SimulatorFetchError.noBootedSimulators
        }

        log("booted simulators: [\(bootedSimulators.map { "\($0.id) \($0.name)" }.joined(separator: ", "))]")

        return [Simulator.empty()] + bootedSimulators
    }
}
