//
//  DiffView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import SwiftUI

struct DiffView: View {
    let diff: FileDiff
    var presentation: DiffPresentation = .fill

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DiffTextViewRepresentable(
            diff: diff,
            presentation: presentation,
            colorScheme: colorScheme
        )
    }
}
