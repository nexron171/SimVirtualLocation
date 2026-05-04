import CoreLocation
import Foundation

enum CoordinateParsing {
    /// Valid geographic ranges; allows negative (west/south) coordinates.
    static func isValid(latitude: Double, longitude: Double) -> Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180
    }
}
