//
//  ContentView.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 20.02.2022.
//

import SwiftUI
import MapKit

struct ContentView: View {

    let mapView: MapView
    @ObservedObject var locationController: LocationController

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            mapView.frame(minWidth: 400)
            VStack {
                GroupBox {
                    Picker("Device mode", selection: $locationController.deviceMode) {
                        Text("Simulator").tag(LocationController.DeviceMode.simulator)
                        Text("Device").tag(LocationController.DeviceMode.device)
                    }.labelsHidden()
                    Picker("Points mode", selection: $locationController.pointsMode) {
                        Text("Single").tag(LocationController.PointsMode.single)
                        Text("Two").tag(LocationController.PointsMode.two)
                    }
                }

                GroupBox {
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

            }.frame(width: 220)
                .pickerStyle(.segmented)
                .padding()
        }.frame(minWidth: 750, minHeight: 500)
            .onAppear {
                locationController.updateMapRegion()
            }
            .modifier(Alert(isPresented: $locationController.showingAlert, text: locationController.alertText))
    }

    init(mapView: MapView, locationController: LocationController) {
        self.mapView = mapView
        self.locationController = locationController
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let mapView = MapView()
        let locationController = LocationController(mapView: mapView)
        ContentView(mapView: mapView, locationController: locationController)
    }
}

struct Alert: ViewModifier {
    let isPresented: Binding<Bool>
    let text: String

    func body(content: Content) -> some View {
        if #available(macOS 12.0, *) {
            content
                .alert(text, isPresented: isPresented) {
                    Text("OK")
                }
        } else {
            content.alert(isPresented: isPresented) {
                SwiftUI.Alert(
                    title: Text(text)
                )
            }
        }
    }
}
