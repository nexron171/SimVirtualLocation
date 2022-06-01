//
//  Runner.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 19.05.2022.
//

import Foundation
import CoreLocation

class Runner {
    
    private let executionQueue = DispatchQueue(label: "runner_queue", qos: .background)
    private var idevicelocationPath: URL?
    
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
        selectedDevice: String,
        showAlert: @escaping (String) -> Void
    ) {
        executionQueue.async {
            let task = self.taskForIOS(args: ["--", "\(location.latitude)", "\(location.longitude)"], selectedDevice: selectedDevice)
            let errorPipe = Pipe()
            
            task.standardError = errorPipe
            
            do {
                try task.run()
            } catch {
                showAlert(error.localizedDescription)
                return
            }
            
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(decoding: errorData, as: UTF8.self)
            
            if !error.isEmpty {
                showAlert("""
                \(error)
                
                Try to install: `brew install libimobiledevice`
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
        let task = taskForIOS(args: ["-s"], selectedDevice: nil)
        
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
    
    private func taskForIOS(args: [String], selectedDevice: String?) -> Process {
        let path: URL = idevicelocationPath ?? Bundle.main.url(forResource: "idevicelocation", withExtension: nil)!
        idevicelocationPath = path
        
        var args = args
        if let selectedDevice = selectedDevice, selectedDevice != "" {
            args = ["-u", selectedDevice] + args
        }
        
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
