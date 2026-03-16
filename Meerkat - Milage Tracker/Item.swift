//
//  Item.swift
//  Meerkat - Milage Tracker
//
//  Created by Rheeder Greeff on 2026-03-15.
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
