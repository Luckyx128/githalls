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
        } else if viewModel.isLoadingDiff {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let diff = viewModel.currentDiff {
            DiffView(diff: diff)
        } else {
            ContentUnavailableView("No diff to show", systemImage: "doc.text")
        }
    }
}
