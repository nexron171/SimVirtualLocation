//
//  iOSPanel.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 18.04.2022.
//

import SwiftUI

struct iOSPanel: View {
    @EnvironmentObject var locationController: LocationController
    
    var body: some View {
        VStack {
            iOSDeviceSettings().environmentObject(locationController)
            LocationSettingsPanel().environmentObject(locationController)
        }
    }
}

struct iOSPanel_Previews: PreviewProvider {
    static var previews: some View {
        iOSPanel()
    }
}
