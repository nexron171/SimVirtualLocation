//
//  AndroidDeviceSettings.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 18.04.2022.
//

import SwiftUI

struct AndroidDeviceSettings: View {
    @EnvironmentObject var locationController: LocationController
    
    var body: some View {
        GroupBox {
            TextField("ADB path", text: $locationController.adbPath)
            TextField("Device ID", text: $locationController.adbDeviceId)
            
            Button(action: {
                locationController.installHelperApp()
            }, label: {
                Text("Install Helper App").frame(maxWidth: .infinity)
            })
        }
    }
}

struct AndroidDeviceSettings_Previews: PreviewProvider {
    static var previews: some View {
        AndroidDeviceSettings()
    }
}
