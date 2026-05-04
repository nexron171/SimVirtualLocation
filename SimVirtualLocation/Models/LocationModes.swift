import Foundation

enum DeviceMode: Int, Identifiable {
    case simulator
    case device

    var id: Int { rawValue }
}

enum PointsMode: Int, Identifiable {
    case single
    case two

    var id: Int { rawValue }
}
