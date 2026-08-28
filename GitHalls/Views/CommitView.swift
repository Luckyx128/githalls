//
//  CommitView.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 28/08/26.
//

import Foundation
import SwiftUI

struct CommitView: View {
    
    @Bindable var viewModel: RepositoryViewModel
    
    private var hasStagedChanges: Bool {
        viewModel.changes.contains{ $0.isStaged }
    }
    
    var body: some View {
        VStack( alignment: .leading, spacing: 6) {
            TextField("Summary", text: $viewModel.commitSummary)
                .textFieldStyle(.roundedBorder)
            
            TextField("Description (optional)", text: $viewModel.commitDescription, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            
            Button {
                Task { await viewModel.commit() }
                
            } label : {
                Text(viewModel.isCommitting ? "Committing..." : "Commit")
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.commitSummary.isEmpty || !hasStagedChanges || viewModel.isCommitting)
        }
        .padding(8)
    }
}
