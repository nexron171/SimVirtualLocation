import Foundation
import CoreLocation

private let kNotificationName = "com.apple.iphonesimulator.simulateLocation"

enum NotificationSender {
    static func postNotification(for coordinate: CLLocationCoordinate2D, to simulators: [String]) {
        let userInfo: [AnyHashable: Any] = [
            "simulateLocationLatitude": coordinate.latitude,
            "simulateLocationLongitude": coordinate.longitude,
            "simulateLocationDevices": simulators,
        ]

        let notification = Notification(name: Notification.Name(rawValue: kNotificationName), object: nil,
                                        userInfo: userInfo)

        DistributedNotificationCenter.default().post(notification)
    }
}
