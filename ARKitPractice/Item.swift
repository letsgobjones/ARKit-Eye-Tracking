//
//  Item.swift
//  ARKitPractice
//
//  Created by Brandon Jones on 11/9/2026.
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
