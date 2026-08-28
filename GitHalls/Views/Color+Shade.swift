//
//  Color+Shade.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 28/08/26.
//
import SwiftUI
import AppKit

extension Color {
    func darker(bytTones tones: Int,toneSize: Double = 0.12) -> Color {
        guard let rgbColor = NSColor(self).usingColorSpace(.deviceRGB) else {
            return self
        }
        
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        
        let newBrightness = max(0, brightness - CGFloat(Double(tones) * toneSize))
        return Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(newBrightness),opacity:  Double(alpha))
    }
}
