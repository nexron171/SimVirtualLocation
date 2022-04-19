//
//  Device.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 21.02.2022.
//

import Foundation

struct Device: Hashable, Identifiable {
    let id: String
    let name: String

    static func empty() -> Device { Device(id: "", name: "To all devices") }
}
