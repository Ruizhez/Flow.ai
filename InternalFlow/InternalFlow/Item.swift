//
//  Item.swift
//  InternalFlow
//
//  Created by Ruizhe Zheng on 4/25/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
