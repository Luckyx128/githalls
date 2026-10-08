//
//  JiraDuration.swift
//  GitHalls
//

import Foundation

/// Durations as Jira people write them: "1w 2d 3h 30m". A day is eight hours
/// and a week five days, as Jira's default time tracking counts them.
enum JiraDuration {
    /// Seconds in the text; nil when it is empty or has anything but
    /// number-and-unit pairs, or adds up to nothing.
    static func seconds(from text: String) -> Int? {
        let units: [Character: Int] = ["w": 5 * 8 * 3600, "d": 8 * 3600, "h": 3600, "m": 60]
        var total = 0
        var number = ""

        for character in text.lowercased() where !character.isWhitespace {
            if character.isNumber {
                number.append(character)
            } else if let unit = units[character], let value = Int(number) {
                total += value * unit
                number = ""
            } else {
                return nil
            }
        }
        return number.isEmpty && total > 0 ? total : nil
    }
}
