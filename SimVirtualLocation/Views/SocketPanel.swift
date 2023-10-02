//
//  SocketPanel.swift
//  SimVirtualLocation
//
//  Created by Anton Prokofev on 09.09.2023.
//

import SwiftUI

struct SocketPanel: View {
    @EnvironmentObject var locationController: LocationController
    
    var body: some View {
        VStack {
            Picker("Device mode", selection: $locationController.socketPanelType) {
                Text("Connection").tag(0)
                Text("WiFi").tag(1)
            }.labelsHidden().pickerStyle(.segmented)
            
            if(locationController.socketPanelType == 0) {
                SocketPanelSettings().environmentObject(locationController.locationSocketServer
                )
            } else {
                WifiPanel().environmentObject(locationController.wifiController)
            }
            LocationSettingsPanel().environmentObject(locationController)
        }
    }
}

struct SocketPanel_Previews: PreviewProvider {
    static var previews: some View {
        SocketPanel()
    }
}
