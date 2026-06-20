//
//  Item.swift
//  Nidus
//
//  Created by Kumare Agape on 20/06/2026.
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
