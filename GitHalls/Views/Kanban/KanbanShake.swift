//
//  KanbanShake.swift
//  GitHalls
//

import SwiftUI

/// A horizontal shake: the board's "no". Driven by an integer that counts
/// refusals, so each increment plays once and the card ends where it started.
struct KanbanShake: GeometryEffect {
    var count: CGFloat

    var animatableData: CGFloat {
        get { count }
        set { count = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(count * .pi * 6), y: 0))
    }
}

/// The spring every board motion shares, or nothing at all when the person has
/// asked the system for less motion.
struct KanbanMotion {
    let reduced: Bool

    var spring: Animation? { reduced ? nil : .spring(response: 0.35, dampingFraction: 0.78) }
    var shake: Animation? { reduced ? nil : .linear(duration: 0.4) }
}
