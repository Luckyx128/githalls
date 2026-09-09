//
//  GraphLanePalette.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 09/09/26.
//

import SwiftUI

/// Colour by lane index, so a column keeps one colour for its whole life.
enum GraphLanePalette {
    private static let base: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]

    static func color(forLane lane: Int) -> Color {
        let hue = base[lane % base.count]
        let cycle = lane / base.count
        // Past the eighth lane, darken rather than repeat: two adjacent columns
        // in the same colour read as one line.
        return cycle == 0 ? hue : hue.darker(bytTones: cycle, toneSize: 0.15)
    }
}
