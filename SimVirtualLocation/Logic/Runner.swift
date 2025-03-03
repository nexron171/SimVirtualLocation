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

    private var isStopped: Bool = false

    // MARK: - Internal Methods

    func stop() {
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

        do {
            try task.run()
            self.runnerQueue.async {
                if self.tasks.count > self.maxTasksCount {
                    self.stop()
                }
                self.tasks.append(task)
            }

            task.waitUntilExit()

            if let errorData = try errorPipe.fileHandleForReading.readToEnd() {
                let error = String(decoding: errorData, as: UTF8.self)

                if !error.isEmpty {
                    showAlert(error)
                }
            }
        } catch {
            showAlert(error.localizedDescription)
            return
        }
    }

    func runOnNewIos(
        location: CLLocationCoordinate2D,
        RSDAddress: String,
        RSDPort: String,
        showAlert: @escaping (String) -> Void
    ) async throws {
        guard !RSDAddress.isEmpty, !RSDPort.isEmpty else {
            showAlert("Please specify RSD ID and Port")
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
                RSDAddress,
                RSDPort,
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
                if self.tasks.count > self.maxTasksCount {
                    self.stop()
                }
                self.tasks.append(task)
            }

            task.waitUntilExit()

            if let errorData = try errorPipe.fileHandleForReading.readToEnd() {
                let error = String(decoding: errorData, as: UTF8.self)

                if !error.isEmpty {
                    showAlert(error)
                }
            }
        } catch {
            showAlert(error.localizedDescription)
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
                showAlert(error.localizedDescription)
                return
            }
            
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(decoding: errorData, as: UTF8.self)
            
            if !error.isEmpty {
                showAlert(error)
            }
        }
    }
    
    func resetIos(showAlert: (String) -> Void) {
        stop()
    }
    
    func resetAndroid(adbDeviceId: String, adbPath: String, showAlert: (String) -> Void) {
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
            showAlert(error.localizedDescription)
        }
        
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let error = String(decoding: errorData, as: UTF8.self)
        
        if !error.isEmpty {
            showAlert(error)
        }
        
        task.waitUntilExit()
    }

    func taskForIOS(args: [String], showAlert: (String) -> Void) async throws -> Process {
        let whichTask = Process()
        let whichURL = URL(fileURLWithPath: "/usr/bin/find")
        let userPath = "/Users/\(NSUserName())/Library"
        whichTask.executableURL = whichURL
        whichTask.currentDirectoryURL = URL(fileURLWithPath: userPath)
        whichTask.arguments = ["Python", "-name", "pymobiledevice3"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        whichTask.standardOutput = outputPipe
        whichTask.standardError = errorPipe

        try whichTask.run()
        whichTask.waitUntilExit()

        if pymobiledevicePath == nil || pymobiledevicePath == "" {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            try outputPipe.fileHandleForReading.close()
            let rawValue = String(decoding: data, as: UTF8.self)
            let sortedPaths = rawValue.split(separator: "\n").sorted{ a, b in
                b.localizedCaseInsensitiveCompare(a) == .orderedDescending
            }

            if let path = sortedPaths.first {
                pymobiledevicePath = "\(userPath)/\(String(path))"
            } else {
                showAlert("""
                pymobiledevice3 not found, it should be installed with python
                to install pymobiledevice3 properly try install it with following command:
                `brew install python3 && python3 -m pip install -U pymobiledevice3 --break-system-packages --user`
                """)
                pymobiledevicePath = ""
            }

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(decoding: errorData, as: UTF8.self)
            if !error.isEmpty {
                showAlert(error)
            }
            try? errorPipe.fileHandleForReading.close()
        }

//        #if arch(arm64)
//        let path: URL = URL(string: "file:///opt/homebrew/bin/pymobiledevice3")!
//        #else
//        let path: URL = URL(string: "file:///usr/local/bin/pymobiledevice3")!
//        #endif

        let path: URL = URL(fileURLWithPath: pymobiledevicePath!)

        let task = Process()
        task.executableURL = path
        task.arguments = args

        return task
    }

    // MARK: - Private Methods

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
