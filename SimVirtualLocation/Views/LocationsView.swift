//
//  LocationsView.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 19.11.2023.
//

import SwiftUI

struct LocationsView: View {

    @EnvironmentObject var locationController: LocationController

    @State private var renameAlertShowing = false
    @State private var updatedName = ""
    @State private var selectedLocation = Location(name: "", latitude: .zero, longitude: .zero)
    @State private var isExporting = false
    @State private var isImporting = false

    var body: some View {
        VStack {
            Text("Locations")

            List {
                ForEach(locationController.savedLocations, id: \.id) { location in
                    VStack(alignment: .leading) {
                        Text(location.name)
                        HStack {
                            Button("To map") {
                                locationController.putLocationOnMap(location: location)
                            }

                            Button("Delete") {
                                locationController.removeLocation(location: location)
                            }

                            Button("Rename") {
                                updatedName = ""
                                selectedLocation = location
                                renameAlertShowing.toggle()
                            }

                            Spacer()
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.25))
                .cornerRadius(8)
            }
            .cornerRadius(16)
            .alert("Rename \(selectedLocation.name)", isPresented: $renameAlertShowing) {
                TextField("Enter new name", text: $updatedName)
                Button("Rename") {
                    locationController.update(selectedLocation, with: updatedName)
                }
                Button("Cancel") {
                    renameAlertShowing.toggle()
                }
            }

            HStack {
                Button("Export") {
                    isExporting.toggle()
                }
                .fileExporter(
                    isPresented: $isExporting,
                    document: LocationsFileDocument(locations: locationController.savedLocations),
                    contentType: .json,
                    defaultFilename: "SimVirtualLocations"
                ) { result in
                        locationController.showAlert("Success")
                    }
                Button("Import") {
                    isImporting.toggle()
                }.fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.json]
                ) { result in
                    let fileResult = result.flatMap { url in
                        read(from: url)
                    }

                    switch fileResult {
                    case .success(let data):
                        locationController.importLocations(from: data)

                    case .failure(let error):
                        locationController.showAlert(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func read(from url: URL) -> Result<Data, Error> {
        let _ = url.startAccessingSecurityScopedResource()

        let result = Result { try Data(contentsOf: url) }

        url.stopAccessingSecurityScopedResource()

        return result
    }
}

struct LocationsView_Previews: PreviewProvider {
    static var previews: some View {
        LocationsView()
    }
}
