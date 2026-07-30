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

    // MARK: - Private Properties

    private let runnerQueue = DispatchQueue(label: "runnerQueue", qos: .background)
    private let executionQueue = DispatchQueue(label: "executionQueue", qos: .background, attributes: .concurrent)
    private var idevicelocationPath: URL?

    private var currentTask: Process?
    private var tasks: [Process] = []
    private let maxTasksCount = 10

    /// PIDs we terminated ourselves while trimming the task window. Their stderr is
    /// expected noise (SIGTERM traceback) and must not surface as a user-facing alert,
    /// because `showAlert` sets `isSimulating = false` and would abort the whole route.
    private var reapedPIDs: Set<Int32> = []

    private var isStopped: Bool = false

    // MARK: - Internal Methods

    func stop() {
        tasks.forEach { $0.terminate() }
        tasks = []
        reapedPIDs = []

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

        do {
            try task.run()
            self.runnerQueue.async {
                // Trim the oldest processes instead of calling stop(): stop() tears down
                // every task and flips isStopped, which silently aborts an in-flight route.
                // The newest task holds the current location, so reaping the oldest is safe.
                while self.tasks.count >= self.maxTasksCount {
                    let old = self.tasks.removeFirst()
                    if old.isRunning {
                        self.reapedPIDs.insert(old.processIdentifier)
                        old.terminate()
                    }
                }
                self.tasks.append(task)
            }

            task.waitUntilExit()

            let wasReaped = self.runnerQueue.sync {
                self.reapedPIDs.remove(task.processIdentifier) != nil
            }

            if !wasReaped, let errorData = try errorPipe.fileHandleForReading.readToEnd() {
                let errorText = String(decoding: errorData, as: UTF8.self)

                if !errorText.isEmpty {
                    Task { @MainActor in
                        showAlert(errorText)
                    }
                }
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
        rsdAddress: String,
        rsdPort: String,
        showAlert: @escaping (String) -> Void
    ) async throws {
        guard !rsdAddress.isEmpty, !rsdPort.isEmpty else {
            Task { @MainActor in
                showAlert("Please specify RSD ID and Port")
            }
            return
        }

        self.isStopped = false

        guard !self.isStopped else {
            return
        }

        let task = try await self.taskForIOS(
            args: [
                "developer",
                "dvt",
                "simulate-location",
                "set",
                "--rsd",
                rsdAddress,
                rsdPort,
                "--",
                "\(location.latitude)",
                "\(location.longitude)"
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

        do {
            try task.run()
            self.runnerQueue.async {
                // Trim the oldest processes instead of calling stop(): stop() tears down
                // every task and flips isStopped, which silently aborts an in-flight route.
                // The newest task holds the current location, so reaping the oldest is safe.
                while self.tasks.count >= self.maxTasksCount {
                    let old = self.tasks.removeFirst()
                    if old.isRunning {
                        self.reapedPIDs.insert(old.processIdentifier)
                        old.terminate()
                    }
                }
                self.tasks.append(task)
            }

            task.waitUntilExit()

            let wasReaped = self.runnerQueue.sync {
                self.reapedPIDs.remove(task.processIdentifier) != nil
            }

            if !wasReaped, let errorData = try errorPipe.fileHandleForReading.readToEnd() {
                let errorText = String(decoding: errorData, as: UTF8.self)

                if !errorText.isEmpty {
                    Task { @MainActor in
                        showAlert(errorText)
                    }
                }
            }
        } catch {
            Task { @MainActor in
                showAlert(error.localizedDescription)
            }
            return
        }
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
