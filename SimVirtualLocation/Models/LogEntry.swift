//
//  LogEntry.swift
//  SimVirtualLocation
//
//  Created by Sergey Shirnin on 21.05.2024.
//

import Foundation

struct LogEntry: Identifiable {

    var id: Date { date }

    let date: Date
    let message: String
}
