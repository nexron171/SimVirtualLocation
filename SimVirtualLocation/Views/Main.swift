//
//  Main.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 20.02.2022.
//

import SwiftUI

@main
struct SimVirtualLocationApp: App {
    var body: some Scene {
        WindowGroup {
            let mapView = MapView()
            let locationController = LocationController(mapView: mapView)
            ContentView(mapView: mapView, locationController: locationController)
        }
    }
}
