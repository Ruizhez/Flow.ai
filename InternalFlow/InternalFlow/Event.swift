//
//  Event.swift
//  InternalFlow
//
//  Created by Ruizhe Zheng on 4/25/25.
//


import Foundation

struct Event: Identifiable, Codable {
    var id = UUID()
    var name: String
    var deadline: Date
    var estimatetimes: Double
    var level: String
}
