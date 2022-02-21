//
//  LocationController.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 21.02.2022.
//

import Combine
import CoreLocation
import MapKit

class LocationController: NSObject, ObservableObject, MKMapViewDelegate, CLLocationManagerDelegate {

    enum DeviceMode: Int, Identifiable {
        case simulator
        case device

        var id: Int { self.rawValue }
    }

    enum PointsMode: Int, Identifiable {
        case single
        case two

        var id: Int { self.rawValue }
    }

    private let mapView: MapView
    private let currentSimulationAnnotation = MKPointAnnotation()

    private let locationManager = CLLocationManager()
    private let simulationQueue = DispatchQueue(label: "simulation", qos: .utility)

    private var isMapCentered = false
    private var annotations: [MKAnnotation] = []
    private var route: MKRoute?
    private var isSimulating = false

    @Published var speed: Double = 60.0
    @Published var pointsMode: PointsMode = .single {
        didSet { handlePointsModeChange() }
    }
    @Published var deviceMode: DeviceMode = .simulator
    @Published var showingAlert: Bool = false
    var alertText: String = ""

    private var timeScale: Double = 0.25
    private var updateTime: UInt32 { UInt32(1000000 * timeScale) }

    init(mapView: MapView) {
        self.mapView = mapView
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone

        mapView.mkMapView.delegate = self
        mapView.clickAction = handleMapClick
        mapView.mkMapView.showsZoomControls = true
    }

    func setCurrentLocation() {
        guard let location = locationManager.location?.coordinate else {
            alertText = "Current location is unavailable"
            showingAlert = true
            return
        }
        run(location: location)
    }

    func setSelectedLocation() {
        guard let annotation = annotations.first else {
            alertText = "Point A is not selected"
            showingAlert = true
            return
        }
        run(location: annotation.coordinate)
    }

    func makeRoute() {
        guard annotations.count == 2 else { return }

        let startPoint = annotations[0].coordinate
        let endPoint = annotations[1].coordinate

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

        self.mapView.mkMapView.removeAnnotations(mapView.mkMapView.annotations)
        self.mapView.mkMapView.showAnnotations([sourceAnnotation, destinationAnnotation], animated: true )

        let directionRequest = MKDirections.Request()
        directionRequest.source = sourceMapItem
        directionRequest.destination = destinationMapItem
        directionRequest.transportType = .automobile

        let directions = MKDirections(request: directionRequest)

        directions.calculate {
            (response, error) -> Void in

            guard let response = response else {
                if let error = error {
                    print("Error: \(error)")
                }

                return
            }

            let route = response.routes[0]

            if let currentRoute = self.route {
                self.mapView.mkMapView.removeOverlay(currentRoute.polyline)
            }
            self.route = route
            self.mapView.mkMapView.addOverlay((route.polyline), level: MKOverlayLevel.aboveRoads)

            let rect = route.polyline.boundingMapRect
            self.mapView.mkMapView.setRegion(MKCoordinateRegion(rect.insetBy(dx: -1000, dy: -1000)), animated: true)
        }
    }

    func simulateRoute() {
        guard let route = route else {
            return
        }

        let buffer = UnsafeBufferPointer(start: route.polyline.points(), count: route.polyline.pointCount)
        var points: [MKMapPoint] = [MKMapPoint]()
        for i in 0..<route.polyline.pointCount {
            points.append(buffer[i])
        }

        guard points.count > 0 else { return }

        isSimulating = true
        simulationQueue.async {
            self.run(location: points[0].coordinate)
            usleep(self.updateTime)

            var index = 0

            while index < points.count && self.isSimulating {
                let speedMS = self.speed / 3.6
                let coordinate = points[index].coordinate
                if index < points.count - 1 {
                    let nextCoordinate = points[index + 1].coordinate
                    let distance = CLLocation.distance(from: coordinate, to: nextCoordinate)

                    if distance <= speedMS {
                        self.run(location: nextCoordinate)
                        DispatchQueue.main.async {
                            self.mapView.mkMapView.removeAnnotation(self.currentSimulationAnnotation)
                            self.currentSimulationAnnotation.coordinate = nextCoordinate
                            self.mapView.mkMapView.addAnnotation(self.currentSimulationAnnotation)
                        }
                    } else {
                        let iterationsCount: Int = Int((distance / speedMS).rounded(.up))

                        var iteration = 0

                        while iteration < iterationsCount && self.isSimulating {
                            let fraction = 0.0 + ((1.0 / Double(iterationsCount)) * Double(iteration))
                            let lon = fraction * nextCoordinate.longitude + (1 - fraction) * coordinate.longitude
                            let lat = fraction * nextCoordinate.latitude + (1 - fraction) * coordinate.latitude
                            let newCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            self.run(location: newCoordinate)
                            DispatchQueue.main.async {
                                self.mapView.mkMapView.removeAnnotation(self.currentSimulationAnnotation)
                                self.currentSimulationAnnotation.coordinate = newCoordinate
                                self.mapView.mkMapView.addAnnotation(self.currentSimulationAnnotation)
                            }
                            iteration += 1
                            usleep(self.updateTime)
                        }
                    }
                }
                index += 1
                usleep(self.updateTime)
            }

            DispatchQueue.main.async {
                self.isSimulating = false
            }
        }
    }

    func updateMapRegion() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            return
        }

        guard !isMapCentered, let location = locationManager.location else { return }

        isMapCentered = true

        mapView.mkMapView.showsUserLocation = true

        let viewRegion = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        let adjustedRegion = mapView.mkMapView.regionThatFits(viewRegion)

        mapView.mkMapView.region = adjustedRegion
    }

    func stopSimulation() {
        isSimulating = false
    }

    func reset() {
        resetAll()
    }

    private func handlePointsModeChange() {
        if pointsMode == .single && annotations.count == 2, let second = annotations.last {
            mapView.mkMapView.removeAnnotation(second)

            if let route = route {
                mapView.mkMapView.removeOverlay(route.polyline)
            }

            annotations = [annotations[0]]
        }
    }

    private func handleMapClick(_ sender: NSClickGestureRecognizer) {
        let point = sender.location(in: mapView.mkMapView)
        handleSet(point: point)
    }

    private func handleSet(point: CGPoint) {
        let clickLocation = mapView.mkMapView.convert(point, toCoordinateFrom: mapView.mkMapView)

        if pointsMode == .single {
            mapView.mkMapView.removeAnnotations(annotations)
            annotations = []
        }

        if annotations.count == 2 {
            mapView.mkMapView.removeAnnotations(mapView.mkMapView.annotations)
            annotations = []
            return
        }

        let annotation = MKPointAnnotation()
        annotation.coordinate = clickLocation
        annotation.title = annotations.count == 0 ? "A" : "B"

        annotations.append(annotation)
        self.mapView.mkMapView.addAnnotation(annotation)
    }

    private func run(location: CLLocationCoordinate2D) {
        if deviceMode == .simulator {
            let bootedSimulators: [Simulator]

            do {
                bootedSimulators = try getBootedSimulators()
            } catch {
                alertText = "\(error)"
                showingAlert = true
                return
            }
            postNotification(for: location, to: bootedSimulators.map { $0.udid.uuidString })
            print("Setting location to \(location.latitude) \(location.longitude)")
            return
        }

        let path = Bundle.main.url(forResource: "idevicelocation", withExtension: nil)!
        let args = ["--", "\(location.latitude)", "\(location.longitude)"]

        let task = Process()
        task.executableURL = path
        task.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            alertText = error.localizedDescription
            showingAlert = true
            return
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        print(output)

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let error = String(decoding: errorData, as: UTF8.self)
        print(error)
    }

    private func resetAll() {
        mapView.mkMapView.removeAnnotations(mapView.mkMapView.annotations)
        annotations = []

        if let route = route {
            mapView.mkMapView.removeOverlay(route.polyline)
        }

        let path = Bundle.main.url(forResource: "idevicelocation", withExtension: nil)!
        let args = ["-s"]

        let task = Process()
        task.executableURL = path
        task.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
        } catch {
            print(error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        print(output)

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let error = String(decoding: errorData, as: UTF8.self)
        print(error)

        task.waitUntilExit()
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(overlay: overlay)
        renderer.strokeColor = NSColor(red: 17.0/255.0, green: 147.0/255.0, blue: 255.0/255.0, alpha: 1)
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

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateMapRegion()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateMapRegion()
    }
}

private extension LocationController {

    func getSimulators(named name: String, from simulators: [Simulator]) throws -> [Simulator] {
        let matchingSimulators = simulators.filter { $0.name.lowercased() == name.lowercased() }
        if matchingSimulators.isEmpty {
            throw SimulatorFetchError.noMatchingSimulators(name: name)
        }

        return matchingSimulators
    }

    func getSimulators(with uuid: UUID, from simulators: [Simulator]) throws -> [Simulator] {
        let matchingSimulators = simulators.filter { $0.udid == uuid }
        if matchingSimulators.isEmpty {
            throw SimulatorFetchError.noMatchingUDID(udid: uuid)
        }

        return matchingSimulators
    }

    func getBootedSimulators() throws -> [Simulator] {
        let task = Process()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "list", "-j", "devices"]

        let pipe = Pipe()
        task.standardOutput = pipe

        task.launch()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        pipe.fileHandleForReading.closeFile()

        if task.terminationStatus != 0 {
            throw SimulatorFetchError.simctlFailed
        }

        let bootedSimulators: [Simulator]

        do {
            bootedSimulators = try JSONDecoder().decode(Simulators.self, from: data).bootedSimulators
        } catch {
            throw SimulatorFetchError.failedToReadOutput
        }

        if bootedSimulators.isEmpty {
            throw SimulatorFetchError.noBootedSimulators
        }

        return bootedSimulators
    }

    enum SimulatorFetchError: Error, CustomStringConvertible {
        case simctlFailed
        case failedToReadOutput
        case noBootedSimulators
        case noMatchingSimulators(name: String)
        case noMatchingUDID(udid: UUID)

        var description: String {
            switch self {
            case .simctlFailed:
                return "Running `simctl list` failed"
            case .failedToReadOutput:
                return "Failed to read output from simctl"
            case .noBootedSimulators:
                return "No simulators are currently booted"
            case .noMatchingSimulators(let name):
                return "No booted simulators named '\(name)'"
            case .noMatchingUDID(let udid):
                return "No booted simulators with udid: \(udid.uuidString)"
            }
        }
    }
}

extension CLLocation {

    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let from = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let to = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return from.distance(from: to)
    }
}
