//
//  Locations.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 19.11.2023.
//

import Foundation
import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct LocationsFileDocument: FileDocument {

    static let readableContentTypes: [UTType] = [.json]

    let locations: [Location]

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            self.locations = try JSONDecoder().decode([Location].self, from: data)
        } else {
            self.locations = []
        }
    }

    init(locations: [Location]) {
        self.locations = locations
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(locations)
        return FileWrapper(regularFileWithContents: data)
    }
}

struct Location: Codable, Identifiable {

    var id: String { "\(latitude)_\(longitude)" }

    let name: String
    let latitude: Double
    let longitude: Double
}
