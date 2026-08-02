import Foundation

/// How to reach an iOS 17+ device for developer services.
enum IOSConnection {

    /// Establish the tunnel in-process with pymobiledevice3's userspace network stack.
    /// Requires no root and no separately started tunnel.
    case userspace(udid: String)

    /// Use a kernel tunnel already started with `pymobiledevice3 remote start-tunnel`,
    /// identified by the RSD address and port it printed.
    case rsd(address: String, port: String)

    /// Arguments selecting this connection, or `nil` when it is not fully configured.
    var arguments: [String]? {
        switch self {
        case .userspace(let udid):
            guard !udid.isEmpty else { return nil }
            return ["--userspace", "--udid", udid]
        case .rsd(let address, let port):
            guard !address.isEmpty, !port.isEmpty else { return nil }
            return ["--rsd", address, port]
        }
    }

    /// Shown while the connection is being established.
    var progressDescription: String {
        switch self {
        case .userspace:
            return "Establishing tunnel to device…"
        case .rsd:
            return "Connecting over RSD tunnel…"
        }
    }

    /// Message shown when `arguments` is `nil`.
    var configurationHint: String {
        switch self {
        case .userspace:
            return "No device selected. Connect an iPhone over USB and press Refresh."
        case .rsd:
            return "Please specify RSD Address and Port"
        }
    }
}
