//
//  DiffDetailView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation
import SwiftUI

struct DiffDetailView: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        if viewModel.selectedChangeID == nil {
            ContentUnavailableView("Select a file", systemImage: "doc.text")
        } else if let diff = viewModel.currentDiff {
            // Checked before `isLoadingDiff` so a redundant reload of the
            // already-selected file (e.g. triggered by a status refresh on
            // window activation) keeps this DiffView's identity stable and
            // just updates it in place, instead of tearing down and
            // recreating the underlying NSTextView — recreating it can race
            // AppKit's layout pass and leave the pane permanently blank.
            DiffView(diff: diff)
        } else if viewModel.isLoadingDiff {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No diff to show", systemImage: "doc.text")
        }
    }
}
