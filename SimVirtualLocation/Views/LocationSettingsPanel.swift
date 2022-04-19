//
//  LocationSettingsPanel.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 18.04.2022.
//

import SwiftUI

struct LocationSettingsPanel: View {
    @EnvironmentObject var locationController: LocationController
    
    var body: some View {
        VStack {
            GroupBox {
                Picker("Points mode", selection: $locationController.pointsMode) {
                    Text("Single").tag(LocationController.PointsMode.single)
                    Text("Two").tag(LocationController.PointsMode.two)
                }.pickerStyle(.segmented)

                Button(action: {
                    locationController.setCurrentLocation()
                }, label: {
                    Text("Set to current location").frame(maxWidth: .infinity)
                })

                Button(action: {
                    locationController.setSelectedLocation()
                }, label: {
                    Text("Set to A point").frame(maxWidth: .infinity)
                })

                Button(action: {
                    locationController.makeRoute()
                }, label: {
                    Text("Make route").frame(maxWidth: .infinity)
                })

                Button(action: {
                    locationController.simulateRoute()
                }, label: {
                    Text("Simulate route").frame(maxWidth: .infinity)
                })

                Button(action: {
                    locationController.stopSimulation()
                }, label: {
                    Text("Stop simulation").frame(maxWidth: .infinity)
                })
            }

            GroupBox {
                VStack(alignment: .leading) {
                    Slider(value: $locationController.speed, in: 5...250) {
                        Text("Speed")
                    }
                    Text("\(Int(locationController.speed.rounded(.up))) km/h")
                }

            }

            Spacer()

            GroupBox {
                Button(action: {
                    locationController.reset()
                }, label: {
                    Text("Reset").frame(maxWidth: .infinity)
                })
            }
        }
    }
}

struct LocationSettingsPanel_Previews: PreviewProvider {
    static var previews: some View {
        LocationSettingsPanel()
    }
}
