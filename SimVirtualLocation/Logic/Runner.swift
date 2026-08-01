//
//  Runner.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 19.05.2022.
//

import Foundation
import CoreLocation

class Runner {

    // MARK: - Internal Properties

    var timeDelay: TimeInterval = 0.5
    var log: ((String) -> Void)?
    var pymobiledevicePath: String?

    /// Reports progress of device operations so the UI can show something during the
    /// seconds a userspace tunnel takes to come up, rather than appearing frozen.
    var onActivity: ((DeviceActivity) -> Void)?

    /// Called with each coordinate `simulate-location play` actually applies, so the map
    /// can follow the device instead of animating on an independent clock.
    var onLocationPlayed: ((Double, Double) -> Void)?

    /// Partial stderr line carried between reads, since chunks split arbitrarily.
    private var playbackLogBuffer = ""

    // MARK: - Private Properties

    private let runnerQueue = DispatchQueue(label: "runnerQueue", qos: .background)
    private let executionQueue = DispatchQueue(label: "executionQueue", qos: .background, attributes: .concurrent)
    private var idevicelocationPath: URL?

    private var currentTask: Process?
    private var tasks: [Process] = []
    /// How many `simulate-location` child processes may be alive at once. Each holds a
    /// DVT channel open; the newest one owns the currently simulated location, and that
    /// location survives its channel closing, so older ones can be retired immediately.
    private let maxLiveTasks = 2

    /// PIDs we terminated ourselves while trimming the task window. Their stderr is
    /// expected noise (SIGTERM traceback) and must not surface as a user-facing alert,
    /// because `showAlert` sets `isSimulating = false` and would abort the whole route.
    private var reapedPIDs: Set<Int32> = []

    private var isStopped: Bool = false

    /// Long-lived `simulate-location play` process for route playback, if one is running.
    private var routePlaybackTask: Process?

    // MARK: - Internal Methods

    func stop() {
        stopRoutePlayback()

        // Record before terminating. The termination handlers run asynchronously and
        // consult this set; clearing it here let a routine SIGTERM traceback reach the
        // user as an alert. Each handler removes its own PID, so the set drains itself.
        runnerQueue.sync {
            for task in tasks where task.isRunning {
                reapedPIDs.insert(task.processIdentifier)
            }
        }

        tasks.forEach { $0.terminate() }
        tasks = []

        isStopped = true
    }
    
    func runOnSimulator(
        location: CLLocationCoordinate2D,
        selectedSimulator: String,
        bootedSimulators: [Simulator],
        showAlert: @escaping (String) -> Void
    ) {
        let simulators = bootedSimulators
            .filter { $0.id == selectedSimulator || selectedSimulator == "" }
            .map { $0.id }

        log?("set simulator location \(location.description)")

        NotificationSender.postNotification(for: location, to: simulators)
    }
    
    func runOnIos(
        location: CLLocationCoordinate2D,
        showAlert: @escaping (String) -> Void
    ) async throws {
        self.isStopped = false

        guard !self.isStopped else {
            return
        }

        let task = try await self.taskForIOS(
            args: [
                "developer",
                "simulate-location",
                "set",
                "--",
                "\(String(format: "%.5f", location.latitude))",
                "\(String(format: "%.5f", location.longitude))"
            ],
            showAlert: showAlert
        )

        self.log?("set iOS location \(location.description)")
        self.log?("task: \(task.logDescription)")

        self.currentTask = task

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.standardInput = inputPipe
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        // `pymobiledevice3 simulate-location set` ends in `OSUTILS.wait_return()`, which
        // parks in `signal.sigwait` and never exits on its own. Blocking here on
        // `waitUntilExit()` therefore holds a Swift cooperative thread forever, and that
        // pool is sized to the CPU core count — so a route stalls after exactly as many
        // waypoints as the Mac has cores. Collect stderr from a termination handler.
        task.terminationHandler = { [weak self] finished in
            guard let self = self else { return }

            let wasReaped = self.runnerQueue.sync {
                self.reapedPIDs.remove(finished.processIdentifier) != nil
            }
            guard !wasReaped else { return }

            // A clean exit is not a failure: `play` logs every waypoint to stderr, so
            // surfacing stderr unconditionally would alert at the end of every route.
            guard finished.terminationStatus != 0 else { return }

            guard let errorData = try? errorPipe.fileHandleForReading.readToEnd() else { return }
            let errorText = String(decoding: errorData, as: UTF8.self)
            guard !errorText.isEmpty else { return }

            self.onActivity?(.failed(Self.summarize(errorText)))

            Task { @MainActor in
                showAlert(errorText)
            }
        }

        // `simulate-location set` prints wait_return()'s "Press Ctrl+C" banner to stdout
        // immediately after the location has been applied — use it as a readiness signal.
        let readyPipe = outputPipe
        readyPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            if String(decoding: chunk, as: UTF8.self).contains("Ctrl+C") {
                readyPipe.fileHandleForReading.readabilityHandler = nil
                self?.onActivity?(.active("Location set"))
            }
        }

        onActivity?(.working("Connecting to device…"))

        do {
            try task.run()

            // Retire older processes rather than calling stop(), which tears down every
            // task and flips isStopped, silently aborting the run in progress.
            self.runnerQueue.async {
                while self.tasks.count >= self.maxLiveTasks {
                    let old = self.tasks.removeFirst()
                    if old.isRunning {
                        self.reapedPIDs.insert(old.processIdentifier)
                        old.terminate()
                    }
                }
                self.tasks.append(task)
            }
        } catch {
            Task { @MainActor in
                showAlert(error.localizedDescription)
            }
            return
        }
    }

    func runOnNewIos(
        location: CLLocationCoordinate2D,
        connection: IOSConnection,
        showAlert: @escaping (String) -> Void
    ) async throws {
        guard let connectionArguments = connection.arguments else {
            Task { @MainActor in
                showAlert(connection.configurationHint)
            }
            return
        }

        self.isStopped = false

        guard !self.isStopped else {
            return
        }

        let task = try await self.taskForIOS(
            args: ["developer", "dvt", "simulate-location", "set"]
                + connectionArguments
                + ["--", "\(location.latitude)", "\(location.longitude)"],
            showAlert: showAlert
        )

        self.log?("set iOS location \(location.description)")
        self.log?("task: \(task.logDescription)")

        self.currentTask = task

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.standardInput = inputPipe
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        // `pymobiledevice3 simulate-location set` ends in `OSUTILS.wait_return()`, which
        // parks in `signal.sigwait` and never exits on its own. Blocking here on
        // `waitUntilExit()` therefore holds a Swift cooperative thread forever, and that
        // pool is sized to the CPU core count — so a route stalls after exactly as many
        // waypoints as the Mac has cores. Collect stderr from a termination handler.
        task.terminationHandler = { [weak self] finished in
            guard let self = self else { return }

            let wasReaped = self.runnerQueue.sync {
                self.reapedPIDs.remove(finished.processIdentifier) != nil
            }
            guard !wasReaped else { return }

            // A clean exit is not a failure: `play` logs every waypoint to stderr, so
            // surfacing stderr unconditionally would alert at the end of every route.
            guard finished.terminationStatus != 0 else { return }

            guard let errorData = try? errorPipe.fileHandleForReading.readToEnd() else { return }
            let errorText = String(decoding: errorData, as: UTF8.self)
            guard !errorText.isEmpty else { return }

            self.onActivity?(.failed(Self.summarize(errorText)))

            Task { @MainActor in
                showAlert(errorText)
            }
        }

        // `simulate-location set` prints wait_return()'s "Press Ctrl+C" banner to stdout
        // immediately after the location has been applied — use it as a readiness signal.
        let readyPipe = outputPipe
        readyPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            if String(decoding: chunk, as: UTF8.self).contains("Ctrl+C") {
                readyPipe.fileHandleForReading.readabilityHandler = nil
                self?.onActivity?(.active("Location set"))
            }
        }

        onActivity?(.working(connection.progressDescription))

        do {
            try task.run()

            // Retire older processes rather than calling stop(), which tears down every
            // task and flips isStopped, silently aborting the run in progress.
            self.runnerQueue.async {
                while self.tasks.count >= self.maxLiveTasks {
                    let old = self.tasks.removeFirst()
                    if old.isRunning {
                        self.reapedPIDs.insert(old.processIdentifier)
                        old.terminate()
                    }
                }
                self.tasks.append(task)
            }
        } catch {
            Task { @MainActor in
                showAlert(error.localizedDescription)
            }
            return
        }
    }

    /// Replay an entire route with a single `simulate-location play` process.
    ///
    /// `play` walks the GPX inside one DVT session, so it neither spawns a child per waypoint
    /// nor holds several device sessions open at once.
    func playRoute(
        gpxURL: URL,
        connection: IOSConnection,
        showAlert: @escaping (String) -> Void
    ) async throws {
        guard let connectionArguments = connection.arguments else {
            Task { @MainActor in
                showAlert(connection.configurationHint)
            }
            return
        }

        stopRoutePlayback()
        self.isStopped = false
        self.playbackLogBuffer = ""

        let task = try await self.taskForIOS(
            args: ["developer", "dvt", "simulate-location", "play", gpxURL.path] + connectionArguments,
            showAlert: showAlert
        )

        self.log?("playing route: \(gpxURL.lastPathComponent)")
        self.log?("task: \(task.logDescription)")

        let errorPipe = Pipe()
        task.standardInput = Pipe()
        task.standardOutput = Pipe()
        task.standardError = errorPipe

        task.terminationHandler = { [weak self] finished in
            guard let self = self else { return }

            let wasReaped = self.runnerQueue.sync {
                self.reapedPIDs.remove(finished.processIdentifier) != nil
            }
            guard !wasReaped else { return }

            // A clean exit is not a failure: `play` logs every waypoint to stderr, so
            // surfacing stderr unconditionally would alert at the end of every route.
            guard finished.terminationStatus != 0 else { return }

            guard let errorData = try? errorPipe.fileHandleForReading.readToEnd() else { return }
            let errorText = String(decoding: errorData, as: UTF8.self)
            guard !errorText.isEmpty else { return }

            self.onActivity?(.failed(Self.summarize(errorText)))

            Task { @MainActor in
                showAlert(errorText)
            }
        }

        // pymobiledevice3 logs every waypoint it applies to stderr. Parse them so the map
        // can track the device exactly, and so the first one marks playback as started.
        var announced = false
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }

            self.playbackLogBuffer += String(decoding: chunk, as: UTF8.self)
            var lines = self.playbackLogBuffer.components(separatedBy: "\n")
            self.playbackLogBuffer = lines.removeLast()

            for line in lines {
                guard let range = line.range(of: "set location to ") else { continue }

                if !announced {
                    announced = true
                    self.onActivity?(.active("Route playing"))
                }

                let parts = line[range.upperBound...].split(separator: " ")
                guard parts.count >= 2,
                      let latitude = Double(parts[0]),
                      let longitude = Double(parts[1]) else { continue }

                self.onLocationPlayed?(latitude, longitude)
            }
        }

        onActivity?(.working(connection.progressDescription))

        do {
            try task.run()
            self.routePlaybackTask = task
        } catch {
            Task { @MainActor in
                showAlert(error.localizedDescription)
            }
        }
    }

    /// First meaningful line of a traceback, for a one-line status message.
    private static func summarize(_ text: String) -> String {
        let line = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty && !$0.hasPrefix("│") && !$0.hasPrefix("╰") && !$0.hasPrefix("╭") }
        return line ?? "Device operation failed"
    }

    /// Terminate route playback, if running. Its stderr is suppressed because a SIGTERM
    /// traceback here is expected rather than an error worth surfacing.
    func stopRoutePlayback() {
        guard let task = routePlaybackTask else { return }
        routePlaybackTask = nil

        guard task.isRunning else { return }
        runnerQueue.sync { _ = reapedPIDs.insert(task.processIdentifier) }

        // A suspended child would not act on SIGTERM until resumed, so continue it first.
        kill(task.processIdentifier, SIGCONT)
        task.terminate()
    }

    /// Whether a route playback process is currently alive. False once its tunnel has
    /// died, in which case resuming means rebuilding the remainder rather than SIGCONT.
    var isPlaybackRunning: Bool {
        routePlaybackTask?.isRunning == true
    }

    /// Suspend route playback where it stands.
    ///
    /// `play` sleeps between waypoints, so SIGSTOP freezes it mid-route and SIGCONT picks
    /// up exactly where it left off — no need to regenerate the route or start over.
    @discardableResult
    func pauseRoutePlayback() -> Bool {
        guard let task = routePlaybackTask, task.isRunning else { return false }
        guard kill(task.processIdentifier, SIGSTOP) == 0 else { return false }
        onActivity?(.working("Route paused"))
        return true
    }

    @discardableResult
    func resumeRoutePlayback() -> Bool {
        guard let task = routePlaybackTask, task.isRunning else { return false }
        guard kill(task.processIdentifier, SIGCONT) == 0 else { return false }
        onActivity?(.active("Route playing"))
        return true
    }

    func runOnAndroid(
        location: CLLocationCoordinate2D,
        adbDeviceId: String,
        adbPath: String,
        isEmulator: Bool,
        showAlert: @escaping (String) -> Void
    ) {
        executionQueue.async {
            let task: Process

            if isEmulator {
                task = self.taskForAndroid(
                    args: [
                        "-s", adbDeviceId,
                        "emu", "geo", "fix",
                        "\(location.longitude)",
                        "\(location.latitude)"
                    ],
                    adbPath: adbPath
                )
            } else {
                task = self.taskForAndroid(
                    args: [
                        "-s", adbDeviceId,
                        "shell", "am", "broadcast",
                        "-a", "send.mock",
                        "-e", "lat", "\(location.latitude)",
                        "-e", "lon", "\(location.longitude)"
                    ],
                    adbPath: adbPath
                )
            }

            self.log?("set Android location \(location.description)")
            self.log?("task: \(task.logDescription)")

            let errorPipe = Pipe()

            task.standardError = errorPipe

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                Task { @MainActor in
                    showAlert(error.localizedDescription)
                }
                return
            }

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(decoding: errorData, as: UTF8.self)

            if !errorText.isEmpty {
                Task { @MainActor in
                    showAlert(errorText)
                }
            }
        }
    }
    
    func resetIos(showAlert: @escaping (String) -> Void) {
        stop()
    }

    func resetAndroid(adbDeviceId: String, adbPath: String, showAlert: @escaping (String) -> Void) {
        let task = taskForAndroid(
            args: [
                "-s", adbDeviceId,
                "shell", "am", "broadcast",
                "-a", "stop.mock"
            ],
            adbPath: adbPath
        )
        
        let errorPipe = Pipe()
        
        task.standardError = errorPipe
        
        do {
            try task.run()
        } catch {
            Task { @MainActor in
                showAlert(error.localizedDescription)
            }
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errorData, as: UTF8.self)

        if !errorText.isEmpty {
            Task { @MainActor in
                showAlert(errorText)
            }
        }
        
        task.waitUntilExit()
    }

    func taskForIOS(args: [String], showAlert: @escaping (String) -> Void) async throws -> Process {
        // Check cache
        if pymobiledevicePath == nil || pymobiledevicePath == "" {
            pymobiledevicePath = findPymobiledevice3Path()

            if pymobiledevicePath == nil {
                // Check if Python is installed
                let pythonCheck = checkPythonInstallation()

                var message = """
                pymobiledevice3 not found. Searched the following locations:
                • System PATH (using 'which' command)
                • /opt/homebrew/bin/
                • /usr/local/bin/
                • /Applications/anaconda3/bin/
                • ~/.local/bin/
                • ~/Library/Python/*/bin/

                """

                if !pythonCheck.isInstalled {
                    message += """
                    ⚠️ Python 3 is not installed!

                    Install Python 3 first:
                    brew install python3

                    Then install pymobiledevice3:
                    python3 -m pip install -U pymobiledevice3 --break-system-packages --user
                    """
                } else {
                    message += """
                    Python version: \(pythonCheck.version ?? "unknown")

                    Installation command:
                    python3 -m pip install -U pymobiledevice3 --break-system-packages --user

                    After installation, verify with: which pymobiledevice3
                    """
                }

                Task { @MainActor in
                    showAlert(message)
                }
                pymobiledevicePath = ""
            }
        }

        guard let validPath = pymobiledevicePath, !validPath.isEmpty else {
            throw NSError(domain: "Runner", code: 1, userInfo: [NSLocalizedDescriptionKey: "pymobiledevice3 not found"])
        }

        let path = URL(fileURLWithPath: validPath)
        let task = Process()
        task.executableURL = path
        task.arguments = args

        // Python block-buffers stdout when it is a pipe rather than a terminal. Without
        // this, `simulate-location set` parks in sigwait before flushing its readiness
        // banner, so the UI would wait for a signal that never arrives.
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        task.environment = environment

        return task
    }

    // MARK: - Private Methods

    private func checkPythonInstallation() -> (isInstalled: Bool, version: String?) {
        let pythonCommands = ["python3", "python"]

        for command in pythonCommands {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            task.arguments = [command]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            do {
                try task.run()
                task.waitUntilExit()

                if task.terminationStatus == 0 {
                    // Found Python, get version
                    let versionTask = Process()
                    versionTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    versionTask.arguments = [command, "--version"]

                    let versionPipe = Pipe()
                    versionTask.standardOutput = versionPipe
                    versionTask.standardError = versionPipe

                    try? versionTask.run()
                    versionTask.waitUntilExit()

                    let versionData = versionPipe.fileHandleForReading.readDataToEndOfFile()
                    let versionString = String(decoding: versionData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                    return (true, versionString)
                }
            } catch {
                continue
            }
        }

        return (false, nil)
    }

    private func findPymobiledevice3Path() -> String? {
        let fileManager = FileManager.default

        // Strategy 1: Use 'which' to find pymobiledevice3 in PATH (fastest and most reliable)
        let whichTask = Process()
        whichTask.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichTask.arguments = ["pymobiledevice3"]

        let whichPipe = Pipe()
        whichTask.standardOutput = whichPipe
        whichTask.standardError = Pipe() // Suppress errors

        do {
            try whichTask.run()
            whichTask.waitUntilExit()

            if whichTask.terminationStatus == 0 {
                let data = whichPipe.fileHandleForReading.readDataToEndOfFile()
                let pathString = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                if !pathString.isEmpty && fileManager.fileExists(atPath: pathString) {
                    return pathString
                }
            }
        } catch {
            // Fall through to manual search
        }

        // Strategy 2: Check common installation paths
        let commonPaths = [
            "/opt/homebrew/bin/pymobiledevice3",              // ARM64 homebrew
            "/usr/local/bin/pymobiledevice3",                 // Intel homebrew
            "/Applications/anaconda3/bin/pymobiledevice3",    // Anaconda
            "\(NSHomeDirectory())/.local/bin/pymobiledevice3" // pip user local
        ]

        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // Strategy 3: Search ~/Library/Python/*/bin/pymobiledevice3
        let libraryPath = "\(NSHomeDirectory())/Library/Python"

        guard fileManager.fileExists(atPath: libraryPath) else {
            return nil
        }

        do {
            let pythonVersions = try fileManager.contentsOfDirectory(atPath: libraryPath)
            let sortedVersions = pythonVersions.sorted().reversed() // Prefer newer versions

            for version in sortedVersions {
                let binPath = "\(libraryPath)/\(version)/bin/pymobiledevice3"
                if fileManager.fileExists(atPath: binPath) {
                    return binPath
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func taskForAndroid(args: [String], adbPath: String) -> Process {
        let path = adbPath
        let task = Process()
        task.executableURL = URL(string: "file://\(path)")!
        task.arguments = args
        
        return task
    }
}

extension CLLocationCoordinate2D {

    var description: String { "\(latitude) \(longitude)" }
}

extension Process {

    var logDescription: String {
        var description: String = ""
        if let executableURL {
            description += "\(executableURL.absoluteString) "
        }

        if let arguments {
            description += "\(arguments.joined(separator: " "))"
        }

        return description
    }
}
