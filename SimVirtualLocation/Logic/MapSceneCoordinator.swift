import AppKit
import CoreLocation
import MapKit

/// Map annotations, route overlay, and `MKMapViewDelegate` — decoupled from device runners and persistence.
final class MapSceneCoordinator: NSObject, MKMapViewDelegate {

    private let mapView: MKMapView
    private var pointAnnotations: [MKPointAnnotation] = []
    private(set) var route: MKRoute?

    let currentSimulationAnnotation = MKPointAnnotation()

    init(mapView: MKMapView) {
        self.mapView = mapView
        super.init()
        mapView.delegate = self
    }

    func handleMapClick(_ sender: NSClickGestureRecognizer, pointsMode: PointsMode) {
        let point = sender.location(in: mapView)
        let clickLocation = mapView.convert(point, toCoordinateFrom: mapView)
        addLocation(coordinate: clickLocation, pointsMode: pointsMode)
    }

    func addLocation(coordinate: CLLocationCoordinate2D, pointsMode: PointsMode) {
        if pointsMode == .single {
            mapView.removeAnnotations(pointAnnotations)
            pointAnnotations = []
        }

        if pointAnnotations.count == 2 {
            mapView.removeAnnotations(mapView.annotations)
            pointAnnotations = []
            return
        }

        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = pointAnnotations.count == 0 ? "A" : "B"

        pointAnnotations.append(annotation)
        mapView.addAnnotation(annotation)
    }

    func annotationEndpoints() -> [MKPointAnnotation] {
        pointAnnotations
    }

    func makeRoute(transportType: TransportType, showAlert: @escaping (String) -> Void) {
        guard pointAnnotations.count == 2 else {
            showAlert("Route requires two points")
            return
        }

        let startPoint = pointAnnotations[0].coordinate
        let endPoint = pointAnnotations[1].coordinate

        let sourcePlacemark = MKPlacemark(coordinate: startPoint, addressDictionary: nil)
        let destinationPlacemark = MKPlacemark(coordinate: endPoint, addressDictionary: nil)

        let sourceMapItem = MKMapItem(placemark: sourcePlacemark)
        let destinationMapItem = MKMapItem(placemark: destinationPlacemark)

        let sourceAnnotation = MKPointAnnotation()
        if let location = sourcePlacemark.location {
            sourceAnnotation.coordinate = location.coordinate
        }

        let destinationAnnotation = MKPointAnnotation()
        if let location = destinationPlacemark.location {
            destinationAnnotation.coordinate = location.coordinate
        }

        mapView.removeAnnotations(mapView.annotations)
        mapView.showAnnotations([sourceAnnotation, destinationAnnotation], animated: true)

        let directionRequest = MKDirections.Request()
        directionRequest.source = sourceMapItem
        directionRequest.destination = destinationMapItem
        directionRequest.transportType = transportType == .driving ? .automobile : .walking

        let directions = MKDirections(request: directionRequest)

        directions.calculate { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let response = response else {
                    if let error = error {
                        showAlert(error.localizedDescription)
                    }
                    return
                }

                let route = response.routes[0]

                if let currentRoute = self.route {
                    self.mapView.removeOverlay(currentRoute.polyline)
                }
                self.route = route
                self.mapView.addOverlay(route.polyline, level: .aboveRoads)

                let rect = route.polyline.boundingMapRect
                self.mapView.setRegion(MKCoordinateRegion(rect.insetBy(dx: -1000, dy: -1000)), animated: true)
            }
        }
    }

    func removeSimulationAnnotationFromMap() {
        mapView.removeAnnotation(currentSimulationAnnotation)
    }

    func placeSimulationAnnotation(at coordinate: CLLocationCoordinate2D) {
        currentSimulationAnnotation.coordinate = coordinate
        mapView.addAnnotation(currentSimulationAnnotation)
    }

    func resetMapVisuals() {
        mapView.removeAnnotations(mapView.annotations)
        pointAnnotations = []

        if let route = route {
            mapView.removeOverlay(route.polyline)
        }
        route = nil
    }

    func handlePointsModeChange(to pointsMode: PointsMode) {
        if pointsMode == .single && pointAnnotations.count == 2, let second = pointAnnotations.last {
            mapView.removeAnnotation(second)

            if let route = route {
                mapView.removeOverlay(route.polyline)
            }

            pointAnnotations = [pointAnnotations[0]]
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(overlay: overlay)
        renderer.strokeColor = NSColor(red: 17.0 / 255.0, green: 147.0 / 255.0, blue: 255.0 / 255.0, alpha: 1)
        renderer.lineWidth = 5.0
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation === currentSimulationAnnotation {
            let marker = MKMarkerAnnotationView(
                annotation: currentSimulationAnnotation,
                reuseIdentifier: "simulationMarker"
            )
            marker.markerTintColor = .orange
            return marker
        }
        return nil
    }
}
