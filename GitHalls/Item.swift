//
//  Item.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
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
