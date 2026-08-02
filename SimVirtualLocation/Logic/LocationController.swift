//
//  LocationController.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 21.02.2022.
//

import Combine
import CoreLocation
import MapKit

class LocationController: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Publishers

    @Published var isSimulating = false
    @Published var speed: Double = 60.0 {
        didSet { scheduleSpeedChange() }
    }
    @Published var pointsMode: PointsMode = .single {
        didSet {
            mapScene.handlePointsModeChange(to: pointsMode)
            if pointsMode == .single {
                clearRouteState()
            }
        }
    }

    @Published var transportType: TransportType = .driving
    @Published var deviceMode: DeviceMode = .simulator
    @Published var xcodePath: String = "/Applications/Xcode.app" {
        didSet { defaults.set(xcodePath, forKey: AppStorageKey.xcodePath) }
    }

    @Published var useRSD: Bool = true

    /// Establish the iOS 17+ tunnel in-process instead of relying on a tunnel the user starts
    /// with `sudo` in Terminal. Removes the need for RSD Address / RSD Port entirely.
    @Published var useUserspace: Bool = true {
        didSet { defaults.set(useUserspace, forKey: AppStorageKey.useUserspace) }
    }

    /// True while an entire route is being replayed by a single `simulate-location play`
    /// process, in which case `performMovement` animates the map but must not also push
    /// locations itself.
    private var isPlayingRoute = false

    /// Progress of the current device operation, shown next to the device picker.
    @Published var activity: DeviceActivity = .idle

    /// True while a simulation is suspended and can be resumed from the same point.
    @Published var isPaused = false

    /// Length of the route currently loaded, in metres. Zero when none is loaded.
    @Published private(set) var routeDistance: CLLocationDistance = 0

    /// Journey time the user wants, in minutes. Applying it derives the speed.
    @Published var targetDurationMinutes: String = ""

    /// Route being played, and how much of it the device has already covered. Used to
    /// rebuild the remainder when the speed changes mid-route.
    private var playbackCoordinates: [CLLocationCoordinate2D] = []
    private var playbackIndex = 0
    private var speedChangeWork: DispatchWorkItem?

    /// How often connected devices are rescanned. Scanning shells out to pymobiledevice3,
    /// so poll briskly only while waiting for a device to appear and back off once one is
    /// attached, where the scan exists just to notice a disconnect.
    private static let deviceScanIntervalWaiting: TimeInterval = 3
    private static let deviceScanIntervalAttached: TimeInterval = 15

    private var deviceMonitorTask: Task<Void, Never>?

    @Published var bootedSimulators: [Simulator] = []
    @Published var selectedSimulator: String = ""

    @Published var connectedDevices: [Device] = []
    @Published var selectedDevice: String = ""

    @Published var showingAlert: Bool = false
    @Published var platform: AppPlatform = .iOS {
        didSet { defaults.set(platform.rawValue, forKey: AppStorageKey.platform) }
    }
    @Published var adbPath: String = ""
    @Published var adbDeviceId: String = ""
    @Published var isEmulator: Bool = false

    @Published var rsdAddress: String = ""
    @Published var rsdPort: String = ""

    @Published var timeScale: Double = 1.5 {
        didSet { runner.timeDelay = timeScale }
    }

    @Published var logs: [LogEntry] = []
    @Published var showLogs: Bool = false

    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    // MARK: - Internal (previews & tests)

    var alertText: String = ""

    // MARK: - Private

    private let mapView: MapView
    private let mapScene: MapSceneCoordinator
    private let runner: DeviceLocationRunning
    private let savedLocationsStore: SavedLocationsStore
    private let locationManager = CLLocationManager()
    private let defaults: UserDefaults = UserDefaults.standard
    private let iOSDeveloperImagePath = "/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport/"
    private let iOSDeveloperImageDmg = "/DeveloperDiskImage.dmg"
    private let iOSDeveloperImageSignature = "/DeveloperDiskImage.dmg.signature"

    private var isMapCentered = false

    private var tracks: [Track] = []
    private var currentTrackIndex: Int = 0
    private var lastTrackLocation: CLLocationCoordinate2D?
    private var tracksTimes: [Track: Double] = [:]

    private var timer: Timer?

    @Published var savedLocations: [Location] = []

    // MARK: - Init

    init(
        mapView: MapView,
        runner: DeviceLocationRunning = Runner(),
        savedLocationsStore: SavedLocationsStore = SavedLocationsStore()
    ) {
        self.mapView = mapView
        self.mapScene = MapSceneCoordinator(mapView: mapView.mkMapView)
        self.runner = runner
        self.savedLocationsStore = savedLocationsStore
        super.init()

        if defaults.object(forKey: AppStorageKey.useUserspace) != nil {
            useUserspace = defaults.bool(forKey: AppStorageKey.useUserspace)
        }

        runner.onLocationPlayed = { [weak self] latitude, longitude in
            DispatchQueue.main.async {
                guard let self = self, self.isPlayingRoute else { return }
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                self.playbackIndex += 1
                self.mapScene.removeSimulationAnnotationFromMap()
                self.mapScene.placeSimulationAnnotation(at: coordinate)
            }
        }

        runner.onActivity = { [weak self] activity in
            DispatchQueue.main.async {
                self?.activity = activity
            }
        }

        runner.log = { [weak self] message in
            DispatchQueue.main.async {
                self?.log(message)
            }
        }

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        locationManager.requestLocation()

        mapView.viewHolder.clickAction = { [weak self] gesture in
            guard let self else { return }
            self.mapScene.handleMapClick(gesture, pointsMode: self.pointsMode)
        }

        Task {
            await refreshDevices()
            startDeviceMonitoring()

            if let p = AppPlatform(rawValue: defaults.integer(forKey: AppStorageKey.platform)) {
                platform = p
            }
            adbPath = defaults.string(forKey: AppStorageKey.adbPath) ?? ""
            adbDeviceId = defaults.string(forKey: AppStorageKey.adbDeviceId) ?? ""
            isEmulator = defaults.bool(forKey: AppStorageKey.isEmulator)
            xcodePath = defaults.string(forKey: AppStorageKey.xcodePath) ?? "/Applications/Xcode.app"

            savedLocations = savedLocationsStore.load()
        }
    }

    // MARK: - Public

    func refreshDevices() async {
        await refreshDevices(silently: false)
    }

    /// - Parameter silently: when true this is a background rescan, so a failure is logged
    ///   rather than raised — a device being unplugged is not an error worth alarming about.
    func refreshDevices(silently: Bool) async {
        bootedSimulators = (try? SimulatorDiscovery.fetchBootedSimulators(log: { [weak self] in self?.log($0) })) ?? []
        if selectedSimulator.isEmpty || !bootedSimulators.contains(where: { $0.id == selectedSimulator }) {
            selectedSimulator = bootedSimulators.first?.id ?? ""
        }

        let previousSelection = selectedDevice
        let previousDevices = connectedDevices

        do {
            connectedDevices = try await IOSUSBDeviceDiscovery.fetchConnectedDevices(
                runner: runner,
                showAlert: { [weak self] in self?.showAlert($0) },
                log: { [weak self] in self?.log($0) }
            )
        } catch {
            connectedDevices = []
            if !silently {
                activity = .failed("Could not list devices — see Logs")
            }
        }

        // Keep the user's choice as long as that device is still attached.
        if connectedDevices.contains(where: { $0.id == previousSelection }) {
            selectedDevice = previousSelection
        } else {
            selectedDevice = connectedDevices.first?.id ?? ""
        }

        let changed = connectedDevices != previousDevices

        if connectedDevices.isEmpty {
            if changed, !previousDevices.isEmpty {
                handleDeviceDisconnected()
            } else if activity == .idle {
                activity = .working("Waiting for a device…")
            }
            return
        }

        guard changed else { return }

        if previousDevices.isEmpty {
            activity = .active("Device connected")
        } else {
            activity = .idle
        }
        log("connected devices: \(connectedDevices.map { $0.name }.joined(separator: ", "))")
    }

    /// The device went away mid-session.
    ///
    /// iOS drops the simulated location as soon as the tunnel dies, so the phone is already
    /// back on real GPS. Say so rather than leaving a stale "Location set" on screen, and
    /// suspend any route instead of resuming it silently — re-spoofing a location the user
    /// is no longer watching is worse than making them press Resume.
    private func handleDeviceDisconnected() {
        log("device disconnected")

        guard isSimulating else {
            activity = .failed("Device disconnected — location no longer simulated")
            return
        }

        runner.stopRoutePlayback()
        timer?.invalidate()
        timer = nil
        isPaused = true
        activity = .failed("Device disconnected — simulation paused")
    }

    /// Rescan for devices on a timer so connecting a phone is noticed without the user
    /// having to ask. Cancelled and restarted rather than left to stack up.
    private func startDeviceMonitoring() {
        deviceMonitorTask?.cancel()
        deviceMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }

                let interval = self.connectedDevices.isEmpty
                    ? Self.deviceScanIntervalWaiting
                    : Self.deviceScanIntervalAttached

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }

                await self.refreshDevices(silently: true)
            }
        }
    }

    func setCurrentLocation() {
        guard let location = locationManager.location?.coordinate else {
            showAlert("Current location is unavailable")
            return
        }
        run(location: location)
    }

    func setSelectedLocation(toBPoint: Bool = false) {
        let endpoints = mapScene.annotationEndpoints()
        if toBPoint {
            guard endpoints.count == 2 else {
                showAlert("Point B is not selected")
                return
            }
            run(location: endpoints[1].coordinate)
        } else {
            guard let annotation = endpoints.first else {
                showAlert("Point A is not selected")
                return
            }
            run(location: annotation.coordinate)
        }
    }

    func makeRoute() {
        mapScene.makeRoute(
            transportType: transportType,
            showAlert: showAlert,
            onRouteReady: { [weak self] route in
                self?.routeDistance = route.distance
            }
        )
    }

    /// Forget everything derived from a route once that route is gone, so distance,
    /// journey time and the duration control do not outlive what they describe.
    private func clearRouteState() {
        routeDistance = 0
        targetDurationMinutes = ""
        tracks = []
        tracksTimes = [:]
        playbackCoordinates = []
        playbackIndex = 0
    }

    /// Distance and journey time for the loaded route at the current speed.
    var routeSummary: String? {
        guard routeDistance > 0 else { return nil }

        let seconds = routeDistance / max(speed / 3.6, 0.1)
        let minutes = Int((seconds / 60).rounded())
        let duration = minutes >= 60
            ? "\(minutes / 60)h \(minutes % 60)m"
            : "\(max(minutes, 1)) min"

        let distance = String(format: "%.2f km", routeDistance / 1000)
        return "\(distance) · about \(duration) at \(Int(speed.rounded())) km/h"
    }

    /// Pick the speed that covers the loaded route in `targetDurationMinutes`.
    ///
    /// Speed is clamped to the slider's range, and the user is told when the requested
    /// time is not achievable within it rather than being given a silently wrong speed.
    func applyTargetDuration() {
        guard routeDistance > 0 else {
            showAlert("Make a route first, then set how long it should take.")
            return
        }

        guard let minutes = Double(targetDurationMinutes.trimmingCharacters(in: .whitespaces)),
              minutes > 0 else {
            showAlert("Enter the journey time in minutes, for example 20.")
            return
        }

        let required = routeDistance / (minutes * 60) * 3.6
        let clamped = min(max(required, Self.minimumSpeed), Self.maximumSpeed)
        speed = (clamped / 5).rounded() * 5

        if required > Self.maximumSpeed || required < Self.minimumSpeed {
            showAlert(
                String(
                    format: "That journey needs %.0f km/h, outside the %.0f–%.0f range. Speed set to %.0f km/h.",
                    required, Self.minimumSpeed, Self.maximumSpeed, speed
                )
            )
        }

        log("target duration \(Int(minutes)) min over \(String(format: "%.2f", routeDistance / 1000)) km — speed set to \(Int(speed)) km/h")
    }

    static let minimumSpeed: Double = 5
    static let maximumSpeed: Double = 200

    func simulateRoute() {
        guard let route = mapScene.route else {
            showAlert("No route for simulation")
            return
        }

        stopSimulation()

        tracks = []
        tracksTimes = [:]

        let buffer = UnsafeBufferPointer(start: route.polyline.points(), count: route.polyline.pointCount)

        for i in 0..<route.polyline.pointCount {
            let trackStartPoint = buffer[i]
            var trackEndPoint: MKMapPoint?
            if i + 1 < route.polyline.pointCount {
                trackEndPoint = buffer[i + 1]
            }

            if let trackEndPoint = trackEndPoint {
                tracks.append(Track(startPoint: trackStartPoint, endPoint: trackEndPoint))
            }
        }

        log("Route segment distances: \(tracks.map { CLLocation.distance(from: $0.startPoint.coordinate, to: $0.endPoint.coordinate) })")

        isPaused = false
        invalidateState()
        isPlayingRoute = startRoutePlayback()

        startMovementTimer()
    }

    func simulateFromAToB() {
        let endpoints = mapScene.annotationEndpoints()
        guard endpoints.count == 2 else {
            showAlert("Route requires two points")
            return
        }

        stopSimulation()
        tracksTimes = [:]
        tracks = [
            Track(
                startPoint: MKMapPoint(endpoints[0].coordinate),
                endPoint: MKMapPoint(endpoints[1].coordinate)
            )
        ]

        // A straight A-to-B run has no MKRoute, so measure the leg directly.
        routeDistance = CLLocation.distance(from: endpoints[0].coordinate, to: endpoints[1].coordinate)

        isPaused = false
        invalidateState()
        isPlayingRoute = startRoutePlayback()

        startMovementTimer()
    }

    func updateMapRegion(force: Bool = false) {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            return
        }

        guard !isMapCentered || force, let location = locationManager.location else {
            locationManager.requestAlwaysAuthorization()
            return
        }

        isMapCentered = true

        mapView.mkMapView.showsUserLocation = true

        let viewRegion = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        let adjustedRegion = mapView.mkMapView.regionThatFits(viewRegion)

        mapView.mkMapView.setRegion(adjustedRegion, animated: true)

        mapView.mkMapView.showsUserLocation = true
    }

    func prepareEmulator() {
        if adbDeviceId.isEmpty {
            showAlert("Please specify device id")
            return
        }

        if adbPath.isEmpty {
            showAlert("Please specify path to adb")
            return
        }

        executeAdbCommand(args: ["shell", "settings", "put", "secure", "location_providers_allowed", "+gps"])
        executeAdbCommand(
            args: ["shell", "settings", "put", "secure", "location_providers_allowed", "+network"],
            successMessage: "Emulator is ready"
        )
    }

    func installHelperApp() {
        if adbDeviceId.isEmpty {
            showAlert("Please specify device id")
            return
        }

        if adbPath.isEmpty {
            showAlert("Please specify path to adb")
            return
        }

        guard let apkURL = Bundle.main.url(forResource: "helper-app", withExtension: "apk") else {
            showAlert("The helper APK is missing from the app bundle.")
            return
        }

        let args = ["-s", adbDeviceId, "install", apkURL.path]

        executeAdbCommand(
            args: args,
            successMessage: "Helper app successfully installed. Please open MockLocationForDeveloper app on your phone and grant all required permissions"
        )
    }

    func stopSimulation() {
        isSimulating = false
        isPlayingRoute = false
        isPaused = false
        runner.stop()
    }

    /// Suspend or resume the running simulation without losing progress.
    func togglePauseSimulation() {
        guard isSimulating else { return }

        if isPaused {
            if isPlayingRoute {
                if runner.isPlaybackRunning {
                    runner.resumeRoutePlayback()
                } else {
                    // Playback died with the connection; replay what is left of the route.
                    restartPlaybackFromCurrentPosition()
                }
            }
            isPaused = false
            startMovementTimer()
            log("simulation resumed")
        } else {
            if isPlayingRoute { runner.pauseRoutePlayback() }
            isPaused = true
            timer?.invalidate()
            timer = nil
            log("simulation paused")
        }
    }

    /// Apply a speed change to a route already in flight.
    ///
    /// The GPX encodes speed as the gap between timestamps, so the only way to change it is
    /// to rewrite the remainder of the route and restart playback from where the device
    /// actually is. Debounced, because dragging the slider emits continuously.
    private func scheduleSpeedChange() {
        speedChangeWork?.cancel()
        guard isSimulating, isPlayingRoute, !isPaused else { return }

        let work = DispatchWorkItem { [weak self] in
            self?.restartPlaybackFromCurrentPosition()
        }
        speedChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func restartPlaybackFromCurrentPosition() {
        guard isSimulating, isPlayingRoute else { return }
        guard !connectedDevices.isEmpty else {
            activity = .failed("No device connected")
            return
        }

        let remaining = Array(playbackCoordinates.suffix(from: min(playbackIndex, playbackCoordinates.count)))
        guard remaining.count > 1 else { return }

        runner.stopRoutePlayback()

        do {
            let url = try GPXRoute.write(coordinates: remaining, speed: speed / 3.6)
            let connection = iosConnection
            playbackCoordinates = remaining
            playbackIndex = 0

            Task {
                try await runner.playRoute(gpxURL: url, connection: connection, showAlert: showAlert)
            }

            log("speed changed to \(Int(speed)) km/h — replaying \(remaining.count) remaining points")
        } catch {
            showAlert(error.localizedDescription)
        }
    }

    private func startMovementTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timeScale, repeats: true) { [weak self] _ in
            self?.performMovement()
        }
    }

    func reset() {
        mapScene.resetMapVisuals()
        clearRouteState()

        if platform == .iOS {
            runner.resetIos(showAlert: showAlert)
        } else {
            runner.resetAndroid(adbDeviceId: adbDeviceId, adbPath: adbPath, showAlert: showAlert)
        }
    }

    func mountDeveloperImage() {
        guard let device = connectedDevices.first(where: { $0.id == selectedDevice }) else {
            showAlert("No selected device")
            return
        }

        Task {
            do {
                let task = try await runner.taskForIOS(
                    args: [
                        "mounter",
                        "mount-developer",
                        "--udid",
                        device.id,
                        makeDeveloperImageDmgPath(iOSVersion: device.version),
                        makeDeveloperImageSignaturePath(iOSVersion: device.version)
                    ],
                    showAlert: showAlert
                )
                let result = try ProcessRunner.run(task)
                Self.presentPymobileDeviceOutput(stdout: result.stdout, stderr: result.stderr, showAlert: showAlert)
            } catch {
                showAlert(error.localizedDescription)
            }
        }
    }

    func unmountDeveloperImage() {
        Task {
            do {
                let task = try await runner.taskForIOS(
                    args: [
                        "mounter",
                        "umount-developer"
                    ],
                    showAlert: showAlert
                )
                let result = try ProcessRunner.run(task)
                Self.presentPymobileDeviceOutput(stdout: result.stdout, stderr: result.stderr, showAlert: showAlert)
            } catch {
                showAlert(error.localizedDescription)
            }
        }
    }

    func savePointA() {
        guard let point = mapScene.annotationEndpoints().first?.coordinate else {
            showAlert("Point A is not selected")
            return
        }

        savedLocations.append(
            Location(
                name: "Point A (\(point.latitude) - \(point.longitude))",
                latitude: point.latitude,
                longitude: point.longitude
            )
        )

        persistSavedLocations()
    }

    func savePointB() {
        let endpoints = mapScene.annotationEndpoints()
        guard endpoints.count == 2, let point = endpoints.last?.coordinate else {
            showAlert("Point B is not selected")
            return
        }

        savedLocations.append(
            Location(
                name: "Point B (\(point.latitude) - \(point.longitude))",
                latitude: point.latitude,
                longitude: point.longitude
            )
        )

        persistSavedLocations()
    }

    func removeLocation(location: Location) {
        savedLocations.removeAll { $0.id == location.id }
        persistSavedLocations()
    }

    func update(_ location: Location, with name: String) {
        guard let locationIndex = savedLocations.firstIndex(where: { $0.id == location.id }) else {
            return
        }

        savedLocations.remove(at: locationIndex)
        savedLocations.insert(
            Location(
                name: name,
                latitude: location.latitude,
                longitude: location.longitude
            ),
            at: locationIndex
        )

        persistSavedLocations()
    }

    func putLocationOnMap(location: Location) {
        mapScene.addLocation(
            coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            pointsMode: pointsMode
        )
    }

    func showAlert(_ text: String) {
        DispatchQueue.main.async {
            self.alertText = text
            self.showingAlert = true
            self.isSimulating = false
            self.log("Alert: \(text)")
        }
    }

    func importLocations(from data: Data) {
        let locations = (try? JSONDecoder().decode([Location].self, from: data)) ?? []

        savedLocations.append(contentsOf: locations)
        persistSavedLocations()
    }

    func setToCoordinate(latString: String = "", lngString: String = "") {
        let lat = Double(latString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .nan
        let lng = Double(lngString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .nan

        guard CoordinateParsing.isValid(latitude: lat, longitude: lng) else {
            showAlert("Invalid coordinates (latitude −90…90, longitude −180…180)")
            return
        }

        putLocationOnMap(location: Location(name: "", latitude: lat, longitude: lng))
        run(location: CLLocationCoordinate2D(latitude: lat, longitude: lng))
    }

    func setToCoordinate(latLngString: String = "") {
        let splitValue = latLngString.components(separatedBy: ",")

        guard latLngString.contains(","), splitValue.count == 2 else {
            showAlert("Use the format latitude, longitude (comma-separated)")
            return
        }

        let latSplitString = splitValue[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let lngSplitString = splitValue[1].trimmingCharacters(in: .whitespacesAndNewlines)

        setToCoordinate(latString: latSplitString, lngString: lngSplitString)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateMapRegion()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateMapRegion()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        log(error.localizedDescription)
    }

    // MARK: - Private

    private func persistSavedLocations() {
        savedLocationsStore.save(savedLocations)
    }

    private func invalidateState() {
        timer?.invalidate()
        timer = nil
        isSimulating = true
        lastTrackLocation = nil
        currentTrackIndex = 0
    }

    /// How the iOS 17+ device should be reached.
    private var iosConnection: IOSConnection {
        useUserspace ? .userspace(udid: selectedDevice) : .rsd(address: rsdAddress, port: rsdPort)
    }

    /// Coordinates along the computed route, in order.
    private func routeCoordinates() -> [CLLocationCoordinate2D] {
        guard let last = tracks.last else { return [] }
        return tracks.map { $0.startPoint.coordinate } + [last.endPoint.coordinate]
    }

    /// Hand the whole route to the device as one `simulate-location play` process.
    ///
    /// - Returns: `true` when playback started, meaning `performMovement` should only animate
    ///   the map rather than pushing a location per waypoint.
    private func startRoutePlayback() -> Bool {
        guard platform == .iOS, deviceMode == .device else { return false }

        let coordinates = routeCoordinates()
        guard coordinates.count > 1 else { return false }

        playbackCoordinates = coordinates
        playbackIndex = 0

        do {
            let url = try GPXRoute.write(coordinates: coordinates, speed: speed / 3.6)
            let connection = iosConnection

            Task {
                try await runner.playRoute(gpxURL: url, connection: connection, showAlert: showAlert)
            }

            log("route playback started (\(coordinates.count) points)")
            return true
        } catch {
            showAlert(error.localizedDescription)
            return false
        }
    }

    private func performMovement() {
        guard isSimulating, tracks.count > 0, currentTrackIndex < tracks.count else {
            isSimulating = false
            isPaused = false
            timer?.invalidate()
            timer = nil
            currentTrackIndex = 0
            printTimesToLog()
            return
        }

        let track = tracks[currentTrackIndex]
        let trackMove = track.getNextLocation(
            from: lastTrackLocation,
            speed: (speed / 3.6) * timeScale
        )

        mapScene.removeSimulationAnnotationFromMap()

        switch trackMove {
        case .moveTo(to: let to, from: let from, withSpeed: let moveSpeed):
            lastTrackLocation = to
            if !isPlayingRoute { run(location: to) }
            mapScene.placeSimulationAnnotation(at: to)
            log("move to — distance=\(CLLocation.distance(from: from, to: to)), speed=\(moveSpeed)")

        case .finishTo(to: let to, from: let from, withSpeed: let moveSpeed):
            lastTrackLocation = nil
            currentTrackIndex += 1
            if !isPlayingRoute { run(location: to) }
            mapScene.placeSimulationAnnotation(at: to)
            log("finish to — distance=\(CLLocation.distance(from: from, to: to)), speed=\(moveSpeed)")
        }

        tracksTimes[track] = (tracksTimes[track] ?? 0) + timeScale
    }

    private func executeAdbCommand(args: [String], successMessage: String? = nil) {
        if adbDeviceId.isEmpty {
            showAlert("Please specify device id")
            return
        }

        if adbPath.isEmpty {
            showAlert("Please specify path to adb")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: adbPath)
        task.arguments = args

        let errorPipe = Pipe()

        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            showAlert(error.localizedDescription)
            return
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errorData, as: UTF8.self)

        if !errorText.isEmpty {
            showAlert(errorText)
        } else if let successMessage = successMessage {
            showAlert(successMessage)
        }
    }

    private func printTimesToLog() {
        tracksTimes.forEach { track, time in
            let distance = CLLocation.distance(from: track.startPoint.coordinate, to: track.endPoint.coordinate)
            let avgSpeed = distance / time
            log("Track result: speed=\(avgSpeed * 3.6) km/h, distance=\(distance), time=\(time)")
        }
    }

    private func run(location: CLLocationCoordinate2D) {
        defaults.set(platform.rawValue, forKey: AppStorageKey.platform)
        defaults.set(adbPath, forKey: AppStorageKey.adbPath)
        defaults.set(adbDeviceId, forKey: AppStorageKey.adbDeviceId)
        defaults.set(isEmulator, forKey: AppStorageKey.isEmulator)

        if platform == .android {
            runOnAndroid(location: location)
            return
        }
        if deviceMode == .device {
            if useRSD {
                Task {
                    try await runner.runOnNewIos(
                        location: location,
                        connection: iosConnection,
                        showAlert: showAlert
                    )
                }

            } else {
                Task {
                    try await runner.runOnIos(
                        location: location,
                        showAlert: showAlert
                    )
                }
            }
        } else {
            if bootedSimulators.isEmpty {
                isSimulating = false
                showAlert(SimulatorFetchError.noBootedSimulators.description)
            }
            runner.runOnSimulator(
                location: location,
                selectedSimulator: selectedSimulator,
                bootedSimulators: bootedSimulators,
                showAlert: showAlert
            )
        }
    }

    private func runOnAndroid(location: CLLocationCoordinate2D) {
        if adbDeviceId.isEmpty {
            showAlert("Please specify device id")
            return
        }

        if adbPath.isEmpty {
            showAlert("Please specify path to adb")
            return
        }

        log("""
        Run on android
        - location: \(location)
        - adbDeviceId: \(adbDeviceId)
        - adbPath: \(adbPath)
        - isEmulator: \(isEmulator)
        """)
        runner.runOnAndroid(
            location: location,
            adbDeviceId: adbDeviceId,
            adbPath: adbPath,
            isEmulator: isEmulator,
            showAlert: showAlert
        )
    }

    private func makeDeveloperImageDmgPath(iOSVersion: String) -> String {
        "\(xcodePath)\(iOSDeveloperImagePath)\(iOSVersion)\(iOSDeveloperImageDmg)"
    }

    private func makeDeveloperImageSignaturePath(iOSVersion: String) -> String {
        "\(xcodePath)\(iOSDeveloperImagePath)\(iOSVersion)\(iOSDeveloperImageSignature)"
    }

    private func log(_ message: String) {
        logs.insert(LogEntry(date: Date(), message: message), at: 0)
    }
    
    func clearLogs() {
        logs.removeAll()
    }

    private static func presentPymobileDeviceOutput(stdout: Data, stderr: Data, showAlert: @escaping (String) -> Void) {
        let err = String(data: stderr, encoding: .utf8) ?? ""
        let out = String(data: stdout, encoding: .utf8) ?? ""

        if !err.isEmpty {
            if err.range(of: "{'Error': 'DeviceLocked'}") != nil {
                showAlert("Error: Device is locked")
            } else {
                showAlert(err)
            }
        }

        if !out.isEmpty {
            showAlert(out)
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
