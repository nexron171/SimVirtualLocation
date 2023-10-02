//
//  SocketPanelSettings.swift
//  SimVirtualLocation
//
//  Created by Anton Prokofev on 09.09.2023.
//

import SwiftUI

struct SocketPanelSettings: View {
//    @EnvironmentObject var locationController: LocationController
    @EnvironmentObject var locationSocketServer: LocationSocketServer
    
    var body: some View {
        GroupBox {
            GroupBox {
                Text("Host server is running: \(String(locationSocketServer.isRunning))")
                
                Button(action: {
                    if(!locationSocketServer.isRunning){
                        do {
                            try? locationSocketServer.start()
                        } catch {}
                    } else {
                        locationSocketServer.stop()
                    }
                }, label: {
                    if(locationSocketServer.isRunning) {
                        Text("Stop").frame(maxWidth: .infinity)
                    } else {
                        Text("Start").frame(maxWidth: .infinity)
                    }
                })
            }
            GroupBox {
                Text("Device is connected? \(String(locationSocketServer.isConnected))")
                Button(action: {
                    locationSocketServer.installMockApp()
                }, label: { Text("install mock app")})
                Button(action: {
                    locationSocketServer.connectDevice()
                }, label: { Text("Re/Connect to device") })
            }
        }
    }
}

struct SocketPanelSettings_Previews: PreviewProvider {
    static var previews: some View {
        SocketPanelSettings()
    }
}
