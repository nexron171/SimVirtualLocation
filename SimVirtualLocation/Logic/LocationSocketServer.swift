//
//  LocationSocketServer.swift
//  SimVirtualLocation
//
//  Created by Anton Prokofev on 08.09.2023.
//

import Foundation
import Network
import CoreLocation

class LocationSocketServer : NSObject, ObservableObject {
    let locationController: LocationController;
    
    init(locationController: LocationController){
        self.locationController = locationController
    }
    
    var listener: NWListener?
    @Published var isRunning = false
    @Published var deviceIP: String = ""
    @Published var isConnected = false;
    let port = "8801"
    
    func start() throws {
        if(isRunning) {
            listener?.cancel()
            listener = nil;
        }
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(port)!)
        print("isRunning")
        isRunning = true
        listener.stateUpdateHandler = self.stateDidChange(to:)
        listener.newConnectionHandler = self.didAccept(connection:)
        listener.start(queue: .main)
        self.listener = listener
    }
    
    func stateDidChange(to newState: NWListener.State) {
        switch newState {
        case .setup:
            break
        case .waiting:
            break
        case .ready:
            break
        case .failed(let error):
            self.listener?.cancel()
            self.listener = nil;
//            self.listenerDidFail(error: error)
        case .cancelled:
            self.listener?.cancel()
            self.listener = nil
            break
        }
    }
    
    var nextID: Int = 0
    
    var currentConnection: NWConnection? = nil;
    
    func didAccept(connection: NWConnection) {
        if(self.isConnected) {
            sendEndOfStream()
            currentConnection?.cancel()
            currentConnection = nil;
        }
        print("Connected")
        currentConnection = connection;
        connection.start(queue: .main)
        self.isConnected = true;
    }
    

    func transferLocation(location: CLLocationCoordinate2D, speed: Double) {
        if let connection = currentConnection {
            
            let latitude = location.latitude
            let longitude = location.longitude
            print("send location \(latitude);\(longitude);speed=\(speed) ")
            let data = Data("lat=\(latitude);lon=\(longitude);speed=\(speed)|".utf8)
            connection.send(content: data, completion: .contentProcessed({ error in
                if let error = error {
                    print(error)
                }
            }))
            
        }
    }
    
    func sendEndOfStream() {
        currentConnection?.send(content: Data("end".utf8), contentContext: .defaultStream, isComplete: true, completion: .contentProcessed({ error in
            if let error = error {
                print(error)
            }
        }))
    }


    
    func stop() {
        sendEndOfStream();
        currentConnection?.cancel();
        currentConnection = nil;
        listener?.cancel()
        listener = nil
        isConnected = false
        isRunning = false
        print("isStop")
    }
    
    func connectDevice() {
        let deviceApi = Int(self.locationController.runShellCommand("adb shell getprop ro.build.version.sdk") ?? "0") ?? 31
        let killArgs = ["shell", "am", "force-stop", "com.devnex.simvirtuallocation"]
        self.locationController.executeAdbCommand(args: killArgs, successMessage: "App killed")
        if let address = locationController.getIPAddress() {
            print("try to connect device by ip \(address)")
            let service = deviceApi > 25 ? "start-foreground-service" : "startservice"
            let args = ["shell", "am", service, "-n", "com.devnex.simvirtuallocation/.LocationSocketService", "--es", "host", "\(address):\(port)"]
            self.locationController.executeAdbCommand(args: args, successMessage: "Complete")
        }
    }
    
    func installMockApp() {
        let apkPath = Bundle.main.url(forResource: "SimVirtualLocationWithSocket.apk", withExtension: "apk")!.path
        let args = ["install", "-r", "-g", apkPath]
        locationController.executeAdbCommand(args: args, successMessage: "Mock Location App installed")
    }
    
}
