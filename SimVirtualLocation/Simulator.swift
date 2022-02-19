import Foundation

struct Simulators: Codable {
    private let devices: [String: [Simulator]]

    var bootedSimulators: [Simulator] {
        return self.devices.flatMap { $1 }.filter { $0.isBooted }
    }
}

struct Simulator: Codable {
    private let state: String
    fileprivate let name: String
    let udid: UUID

    var isBooted: Bool {
        return self.state == "Booted"
    }
}

func getSimulators(named name: String, from simulators: [Simulator]) throws -> [Simulator] {
    let matchingSimulators = simulators.filter { $0.name.lowercased() == name.lowercased() }
    if matchingSimulators.isEmpty {
        throw SimulatorFetchError.noMatchingSimulators(name: name)
    }

    return matchingSimulators
}

func getSimulators(with uuid: UUID, from simulators: [Simulator]) throws -> [Simulator] {
    let matchingSimulators = simulators.filter { $0.udid == uuid }
    if matchingSimulators.isEmpty {
        throw SimulatorFetchError.noMatchingUDID(udid: uuid)
    }

    return matchingSimulators
}

func getBootedSimulators() throws -> [Simulator] {
    let task = Process()
    task.launchPath = "/usr/bin/xcrun"
    task.arguments = ["simctl", "list", "-j", "devices"]

    let pipe = Pipe()
    task.standardOutput = pipe

    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    pipe.fileHandleForReading.closeFile()

    if task.terminationStatus != 0 {
        throw SimulatorFetchError.simctlFailed
    }

    do {
        return try JSONDecoder().decode(Simulators.self, from: data).bootedSimulators
    } catch {
        throw SimulatorFetchError.failedToReadOutput
    }
}

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
