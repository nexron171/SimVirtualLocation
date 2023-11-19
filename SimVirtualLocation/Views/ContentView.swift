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
            ZStack(alignment: .bottomTrailing) {
                mapView.frame(minWidth: 400)
                VStack {
                    Image(systemName: "plus")
                        .foregroundColor(Color.white)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary)
                        .opacity(0.5)
                        .cornerRadius(16)
                        .onTapGesture {
                            var region: MKCoordinateRegion = mapView.mkMapView.region
                            region.span.latitudeDelta /= 2.0
                            region.span.longitudeDelta /= 2.0
                            mapView.mkMapView.setRegion(region, animated: true)
                        }
                    Image(systemName: "minus")
                        .foregroundColor(Color.white)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary)
                        .opacity(0.5)
                        .cornerRadius(16)
                        .onTapGesture {
                            var region: MKCoordinateRegion = mapView.mkMapView.region
                            region.span.latitudeDelta *= 2.0
                            region.span.longitudeDelta *= 2.0
                            mapView.mkMapView.setRegion(region, animated: true)
                        }
                    Image(systemName: "location")
                        .foregroundColor(Color.white)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary)
                        .opacity(0.5)
                        .cornerRadius(16)
                        .onTapGesture {
                            locationController.updateMapRegion(force: true)
                        }
                }.padding()
            }

            VStack {
                Picker("Device mode", selection: $locationController.deviceType) {
                    Text("iOS").tag(0)
                    Text("Android").tag(1)
                }.labelsHidden().pickerStyle(.segmented)
                
                if locationController.deviceType == 0 {
                    iOSPanel()
                        .environmentObject(locationController)
                } else {
                    AndroidPanel()
                        .environmentObject(locationController)
                }
                
            }.frame(width: 250)
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 0))

            LocationsView()
                .environmentObject(locationController)
                .frame(width: 300)
                .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            
        }.frame(minWidth: 1100, minHeight: 500)
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
