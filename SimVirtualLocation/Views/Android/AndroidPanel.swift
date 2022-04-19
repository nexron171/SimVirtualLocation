//
//  AndroidPanel.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 18.04.2022.
//

import SwiftUI

struct AndroidPanel: View {
    @EnvironmentObject var locationController: LocationController
    
    var body: some View {
        VStack {
            AndroidDeviceSettings().environmentObject(locationController)
            LocationSettingsPanel().environmentObject(locationController)
        }
    }
}

struct AndroidPanel_Previews: PreviewProvider {
    static var previews: some View {
        AndroidPanel()
    }
}
