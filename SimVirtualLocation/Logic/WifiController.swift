//
//  WifiController.swift
//  SimVirtualLocation
//
//  Created by Anton Prokofev on 14.09.2023.
//

import Foundation

class WifiController: NSObject, ObservableObject {
    let locationController: LocationController
    
    init(locationController: LocationController) {
        self.locationController = locationController
    }
    
    @Published var ssid: String = ""
    @Published var password: String = ""
    @Published var useProxy: Bool = true
    
    func installWifiApp(){
        let apkPath = Bundle.main.url(forResource: "adb-join-wifi", withExtension: "apk")!.path
        let args = ["install", apkPath]
        locationController.executeAdbCommand(args: args, successMessage: "WiFi App installed")
    }
    
    func connectToWifi() {
        if ssid.isEmpty {
            locationController.showAlert("SSID is empty")
            return
        }
        if let address = locationController.getIPAddress() {
            var args = ["shell", "am", "start", "-n", "com.steinwurf.adbjoinwifi/.MainActivity"]
            let ssidArgs = ["-e", "ssid", ssid]
            if password.isEmpty {
                args += ssidArgs
            } else {
                let passwordArgs = ["-e", "password_type", "WPA", "-e", "password", password]
                args += ssidArgs + passwordArgs
            }
            if useProxy {
                args += ["-e", "proxy_host", address, "-e", "proxy_port", "8888"]
            }
            
            locationController.executeAdbCommand(args: args, successMessage: "WiFi App try to connect")
        }
    }
    
}
