//
//  Device.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 21.02.2022.
//

import Foundation

struct Device: Hashable, Identifiable, Decodable {

    private enum CodingKeys: String, CodingKey {
        case id = "Identifier"
        case name = "DeviceName"
        case version = "ProductVersion"
    }

    let id: String
    let name: String
    let version: String
}
