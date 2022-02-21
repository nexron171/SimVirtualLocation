import Foundation

struct Simulators: Codable {
    private let devices: [String: [Simulator]]

    var bootedSimulators: [Simulator] {
        return self.devices.flatMap { $1 }.filter { $0.isBooted }
    }
}

struct Simulator: Codable {
    private let state: String
    let name: String
    let udid: UUID

    var isBooted: Bool {
        return self.state == "Booted"
    }
}
