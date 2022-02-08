//
//  ViewController.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 07.02.2022.
//

import Cocoa
import MapKit
import CoreLocation
import AppKit

class ViewController: NSViewController, MKMapViewDelegate, CLLocationManagerDelegate {

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var speedLabel: NSTextField!
    @IBOutlet weak var speedSlider: NSSlider!

    let locationManager = CLLocationManager()
    let simulationQueue = DispatchQueue(label: "simulation", qos: .utility)

    var isMapCentered = false
    var annotations: [MKAnnotation] = []
    var route: MKRoute?
    var isSimulating = false
    var speed = 60.0

    override func viewDidLoad() {
        super.viewDidLoad()

        let clickGesture = NSClickGestureRecognizer(
            target: self,
            action: #selector(self.handleMapClick(_:)))

        mapView.delegate = self
        mapView.addGestureRecognizer(clickGesture)

        speedLabel.stringValue = "\(speedSlider.doubleValue)"

        speedSlider.target = self
        speedSlider.action = #selector(onSliderValueChanged)
        speedSlider.isContinuous = true

        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()

        locationManager.delegate = self
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        if !isMapCentered {
            updateMapRegion()
        }
    }

    @IBAction func onClickSetCurrentLocation(_ sender: Any) {
        guard let location = locationManager.location?.coordinate else { return }
        run(location: location)
    }

    @IBAction func onSetSelectedLocation(_ sender: Any) {
        guard let annotation = annotations.first else { return }
        run(location: annotation.coordinate)
    }

    @IBAction func onMakeRoute(_ sender: Any) {
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

        self.mapView.removeAnnotations(mapView.annotations)
        self.mapView.showAnnotations([sourceAnnotation,destinationAnnotation], animated: true )

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
                self.mapView.removeOverlay(currentRoute.polyline)
            }
            self.route = route
            self.mapView.addOverlay((route.polyline), level: MKOverlayLevel.aboveRoads)

            let rect = route.polyline.boundingMapRect
            self.mapView.setRegion(MKCoordinateRegion(rect.insetBy(dx: -1000, dy: -1000)), animated: true)
        }
    }

    @IBAction func onSimulateRoute(_ sender: Any) {
        guard let route = route else {
            return
        }

        let speedMS = speed / 3.6

        let buffer = UnsafeBufferPointer(start: route.polyline.points(), count: route.polyline.pointCount)
        var points: [MKMapPoint] = [MKMapPoint]()
        for i in 0..<route.polyline.pointCount {
            points.append(buffer[i])
        }

        guard points.count > 0 else { return }

        isSimulating = true
        simulationQueue.async {
            self.run(location: points[0].coordinate)
            sleep(1)

            var index = 0

            while index < points.count && self.isSimulating {
                let coordinate = points[index].coordinate
                if index < points.count - 1 {
                    let nextCoordinate = points[index + 1].coordinate
                    let distance = CLLocation.distance(from: coordinate, to: nextCoordinate)

                    if distance <= speedMS {
                        self.run(location: nextCoordinate)
                    } else {
                        let iterationsCount: Int = Int((distance / speedMS).rounded(.up))

                        var iteration = 0

                        while iteration < iterationsCount && self.isSimulating {
                            let fraction = 0.0 + ((1.0 / Double(iterationsCount)) * Double(iteration))
                            let lon = fraction * nextCoordinate.longitude + (1 - fraction) * coordinate.longitude
                            let lat = fraction * nextCoordinate.latitude + (1 - fraction) * coordinate.latitude
                            let newCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                            self.run(location: newCoordinate)
                            iteration += 1
                            sleep(1)
                        }
                    }
                }
                index += 1
                sleep(1)
            }

            DispatchQueue.main.async {
                self.isSimulating = false
            }
        }
    }

    @IBAction func onStopSimulation(_ sender: Any) {
        isSimulating = false
    }

    @objc func onSliderValueChanged() {
        speed = speedSlider.doubleValue.rounded(.up)
        speedLabel.stringValue = "\(speed)"
    }

    func run(location: CLLocationCoordinate2D) {
        let path = Bundle.main.url(forResource: "set-simulator-location", withExtension: nil)!
        let args = ["-c", "\(location.latitude)", "\(location.longitude)"]

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

    @objc func handleMapClick(_ sender: NSClickGestureRecognizer) {
        let point = sender.location(in: mapView)

        let clickLocation = mapView.convert(point, toCoordinateFrom: mapView)

        if annotations.count == 2 {
            mapView.removeAnnotations(annotations)
            annotations = []
            return
        }

        let annotation = MKPointAnnotation()
        annotation.coordinate = clickLocation
        annotation.title = annotations.count == 0 ? "A" : "B"

        annotations.append(annotation)

        mapView.addAnnotation(annotation)
    }

    func updateMapRegion() {
        guard !isMapCentered, let location = locationManager.location else { return }

        isMapCentered = true

        mapView.showsUserLocation = true
        mapView.setCenter(
            location.coordinate,
            animated: false
        )

        let viewRegion = MKCoordinateRegion(center: mapView.centerCoordinate, latitudinalMeters: 500, longitudinalMeters: 500)
        let adjustedRegion = mapView.regionThatFits(viewRegion)

        mapView.region = adjustedRegion
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(overlay: overlay)
        renderer.strokeColor = NSColor(red: 17.0/255.0, green: 147.0/255.0, blue: 255.0/255.0, alpha: 1)
        renderer.lineWidth = 5.0
        return renderer
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateMapRegion()
    }
}

extension CLLocation {

    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let from = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let to = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return from.distance(from: to)
    }
}
