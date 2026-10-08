//
//  HoverHighlight.swift
//  GitHalls
//
//  Hover feedback for plain and borderless buttons: a pointing hand and a
//  soft background while the pointer is over them.
//

import SwiftUI

private struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.12 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering = $0 }
            .pointerStyle(.link)
    }
}

extension View {
    /// Pointing hand plus a background on hover, for plain or borderless buttons.
    func hoverHighlight(cornerRadius: CGFloat = 5) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}
