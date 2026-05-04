import CoreLocation
import Foundation

/// Abstraction over simulator / USB iOS / RSD iOS / Android injection for tests and composition.
protocol DeviceLocationRunning: IOSProcessLaunching {
    var timeDelay: TimeInterval { get set }
    var log: ((String) -> Void)? { get set }
    var pymobiledevicePath: String? { get set }

    func stop()

    func runOnSimulator(
        location: CLLocationCoordinate2D,
        selectedSimulator: String,
        bootedSimulators: [Simulator],
        showAlert: @escaping (String) -> Void
    )

    func runOnIos(
        location: CLLocationCoordinate2D,
        showAlert: @escaping (String) -> Void
    ) async throws

    func runOnNewIos(
        location: CLLocationCoordinate2D,
        rsdAddress: String,
        rsdPort: String,
        showAlert: @escaping (String) -> Void
    ) async throws

    func runOnAndroid(
        location: CLLocationCoordinate2D,
        adbDeviceId: String,
        adbPath: String,
        isEmulator: Bool,
        showAlert: @escaping (String) -> Void
    )

    func resetIos(showAlert: @escaping (String) -> Void)
    func resetAndroid(adbDeviceId: String, adbPath: String, showAlert: @escaping (String) -> Void)
}

extension Runner: DeviceLocationRunning {}
