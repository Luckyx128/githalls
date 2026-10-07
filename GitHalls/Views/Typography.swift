//
//  Typography.swift
//  GitHalls
//

import SwiftUI

/// The app's type scale. On macOS the system sizes are: body 13, callout 12,
/// subheadline 11, caption 10, so `.callout` is reserved for footnotes.
extension Font {
    /// Primary row content: commit summaries, file names, branch names, card titles.
    static let rowPrimary: Font = .body
    /// Secondary metadata: author, date, counts, sublabels.
    static let rowSecondary: Font = .callout
    /// Monospaced hashes and counts, sized to match `rowSecondary`.
    static let rowMono: Font = .system(.callout, design: .monospaced)
    /// Helper text under form fields and inline status messages.
    static let helper: Font = .callout
    /// Genuinely tertiary hints and footnotes.
    static let footnote2: Font = .callout
}
