//
//  MapView.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 20.02.2022.
//

import MapKit
import SwiftUI

final class MapView: NSViewRepresentable {

    typealias NSViewType = MKMapView

    private let mapView = MKMapView()
    var mkMapView: MKMapView { mapView }

    var clickAction: (NSClickGestureRecognizer) -> Void = {_ in }

    func makeNSView(context: Context) -> MKMapView {
        let clickGesture = NSClickGestureRecognizer(
            target: self,
            action: #selector(self.handleClickGesture(_:)))
        clickGesture.numberOfClicksRequired = 1
        mapView.addGestureRecognizer(clickGesture)

        return mapView
    }

    func updateNSView(_ nsView: MKMapView, context: Context) { }

    @objc private func handleClickGesture(_ sender: NSClickGestureRecognizer) {
        clickAction(sender)
    }
}
