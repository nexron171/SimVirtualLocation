//
//  Track.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 24.04.2022.
//

import Foundation
import CoreLocation
import MapKit

struct Track {
    
    enum TrackLocationResult {
        case moveTo(to: CLLocationCoordinate2D, from: CLLocationCoordinate2D, withSpeed: Double)
        case finishTo(to: CLLocationCoordinate2D, from: CLLocationCoordinate2D, withSpeed: Double)
    }
    
    let startPoint: MKMapPoint
    let endPoint: MKMapPoint
    
    func getNextLocation(from: CLLocationCoordinate2D?, speed: Double) -> TrackLocationResult {
        let startLocation = from ?? startPoint.coordinate
        let endLocation = endPoint.coordinate
        
        let distanceToEnd = CLLocation.distance(from: startLocation, to: endLocation)
        
        if distanceToEnd <= speed {
            return .finishTo(to: endLocation, from: startLocation, withSpeed: speed)
        } else {
            let iterationsCount = distanceToEnd / speed
            let fraction = 1.0 / Double(iterationsCount) * Double(1)
            let lon = fraction * endLocation.longitude + (1 - fraction) * startLocation.longitude
            let lat = fraction * endLocation.latitude + (1 - fraction) * startLocation.latitude
            
            return .moveTo(to: CLLocationCoordinate2D(latitude: lat, longitude: lon), from: startLocation, withSpeed: speed)
        }
    }
}
