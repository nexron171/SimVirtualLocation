//
//  WifiPanel.swift
//  SimVirtualLocation
//
//  Created by Anton Prokofev on 14.09.2023.
//

import SwiftUI

struct WifiPanel: View {
    @EnvironmentObject var wifiController: WifiController
    
    var body: some View {
        GroupBox {
            GroupBox(content: {
                Button(action: {
                    wifiController.installWifiApp()
                }, label: { Text("install WiFi app")})
                TextField("SSID", text: $wifiController.ssid)
                TextField("Password", text: $wifiController.password)
                Button(action: {
                    wifiController.connectToWifi()
                },label: {Text("Try to connect")})
                Toggle("Use proxy", isOn: $wifiController.useProxy)
            })
        }
    }
}
