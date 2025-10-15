//
//  Item.swift
//  InternalFlow iphone app
//
//  Created by Ruizhe Zheng on 4/26/25.
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
