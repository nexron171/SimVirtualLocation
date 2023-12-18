//
//  LocationSettingsPanel.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 18.04.2022.
//

import SwiftUI
import Foundation

struct LocationSettingsPanel: View {
    @EnvironmentObject var locationController: LocationController
    
    @State private var isPresentedSetToCoordinate = false
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var latitudeLongitude = ""
    
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
                    latitude = ""
                    longitude = ""
                    latitudeLongitude = ""
                    isPresentedSetToCoordinate = true
                }, label: {
                    Text("Set to Coordinate").frame(maxWidth: .infinity)
                })
                .alert("Enter your coordinate", isPresented: $isPresentedSetToCoordinate) {
                    
                    TextField("Latitude", text: $latitude)
                    
                    TextField("longitude", text: $longitude)
                    
                    TextField("longitude, longitude", text: $latitudeLongitude)
                  
                    Button("Move"){
                      
                        locationController.setToCoordinate(latString: latitude,
                                                           lngString: longitude,
                                                           latLngString: latitudeLongitude)
                    }
                    
                    Button("Cancel", role: .cancel) { }
                }

                HStack {
                    Button(action: {
                        locationController.setSelectedLocation()
                    }, label: {
                        Text("Set to A").frame(maxWidth: .infinity)
                    })
                    Button(action: {
                        locationController.savePointA()
                    }, label: {
                        Text("Save point A").frame(maxWidth: .infinity)
                    })
                }
                
                HStack {
                    Button(action: {
                        locationController.setSelectedLocation(toBPoint: true)
                    }, label: {
                        Text("Set to B").frame(maxWidth: .infinity)
                    })
                    Button(action: {
                        locationController.savePointB()
                    }, label: {
                        Text("Save point B").frame(maxWidth: .infinity)
                    })
                }

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
                    locationController.simulateFromAToB()
                }, label: {
                    Text("Simulate from A to B").frame(maxWidth: .infinity)
                })

                Button(action: {
                    locationController.stopSimulation()
                }, label: {
                    Text("Stop simulation").frame(maxWidth: .infinity)
                })
            }

            GroupBox {
                VStack(alignment: .leading) {
                    Slider(value: $locationController.speed, in: 5...200, step: 5) {
                        Text("Speed")
                    }
                    Text("\(Int(locationController.speed.rounded(.up))) km/h")
                }
            }
            
            GroupBox {
                if locationController.useRSD {
                    Picker("Location update frequency", selection: $locationController.timeScale) {
                        Text("5s").tag(5.0)
                        Text("10s").tag(10.0)
                        Text("15s").tag(15.0)
                    }
                    .pickerStyle(.segmented)
                    .disabled(locationController.isSimulating)
                    .onAppear {
                        locationController.timeScale = 5.0
                    }
                } else {
                    Picker("Location update frequency", selection: $locationController.timeScale) {
                        Text("1s").tag(1.0)
                        Text("1.5s").tag(1.5)
                        Text("2s").tag(2.0)
                    }
                    .pickerStyle(.segmented)
                    .disabled(locationController.isSimulating)
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
