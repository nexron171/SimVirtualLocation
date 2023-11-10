//
//  Runner.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 19.05.2022.
//

import Foundation
import CoreLocation

class Runner {

    var timeDelay: TimeInterval = 0.5

    private let runnerQueue = DispatchQueue(label: "runnerQueue", qos: .background)
    private let executionQueue = DispatchQueue(label: "executionQueue", qos: .background, attributes: .concurrent)
    private var idevicelocationPath: URL?

    private var tasks: [Process] = []

    private var isStopped: Bool = false

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

        NotificationSender.postNotification(for: location, to: simulators)
    }
    
    func runOnIos(
        location: CLLocationCoordinate2D,
        showAlert: @escaping (String) -> Void
    ) {
        self.isStopped = false

        executionQueue.async {
            guard !self.isStopped else {
                return
            }

            let task = self.taskForIOS(
                args: [
                    "developer",
                    "dvt",
                    "simulate-location",
                    "set",
                    "\(location.latitude)",
                    "\(location.longitude)"
                ]
            )

            let errorPipe = Pipe()

            task.standardError = errorPipe

            do {
                try task.run()
                self.runnerQueue.async {
                    if self.tasks.count > 100 {
                        self.stop()
                    }
                    self.tasks.append(task)
                }
            } catch {
                showAlert(error.localizedDescription)
                return
            }

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(decoding: errorData, as: UTF8.self)

            if !error.isEmpty {
                showAlert("""
                \(error)

                Try to install: pymobiledevice3
                `python3 -m pip install -U pymobiledevice3`
                """)
            }
        }
    }

    func runOnNewIos(
        location: CLLocationCoordinate2D,
        RSDAddress: String,
        RSDPort: String,
        showAlert: @escaping (String) -> Void
    ) {
        guard !RSDAddress.isEmpty, !RSDPort.isEmpty else {
            showAlert("Please specify RSD ID and Port")
            return
        }

        self.isStopped = false

        executionQueue.async {
            guard !self.isStopped else {
                return
            }

            let task = self.taskForIOS(
                args: [
                    "developer",
                    "dvt",
                    "simulate-location",
                    "set",
                    "--rsd",
                    RSDAddress,
                    RSDPort,
                    "\(location.latitude)",
                    "\(location.longitude)"
                ]
            )

            let errorPipe = Pipe()
            task.standardError = errorPipe

            do {
                try task.run()
                self.runnerQueue.async {
                    if self.tasks.count > 100 {
                        self.stop()
                    }
                    self.tasks.append(task)
                }
            } catch {
                showAlert(error.localizedDescription)
                return
            }

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(decoding: errorData, as: UTF8.self)

            if !error.isEmpty {
                showAlert("""
                \(error)

                Try to install: pymobiledevice3
                `python3 -m pip install -U pymobiledevice3`
                """)
            }
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

    func taskForIOS(args: [String]) -> Process {
        #if arch(arm64)
        let path: URL = URL(string: "file:///opt/homebrew/bin/pymobiledevice3")!
        #else
        let path: URL = URL(string: "file:///usr/local/bin/pymobiledevice3")!
        #endif

        let task = Process()
        task.executableURL = path
        task.arguments = args

        return task
    }
    
    private func taskForAndroid(args: [String], adbPath: String) -> Process {
        let path = adbPath
        let task = Process()
        task.executableURL = URL(string: "file://\(path)")!
        task.arguments = args
        
        return task
    }
}
