//
//  RepositoryViewModel.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//
import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class RepositoryViewModel {
    private let gitService = GitService()
    
    var repositoryURL: URL?
    var changes: [FileChange] = []
    var selectedChangeID: FileChange.ID?
    var errorMessage: String?
    
    var currentDiff: FileDiff?
    var isLoadingDiff = false

    var selectedChange: FileChange? {
        changes.first { $0.id == selectedChangeID }
    }
    
    var allStaged: Bool {
        !changes.isEmpty && changes.allSatisfy { $0.isStaged }
    }
    
    var currentBranch: String?
    
    var commitSummary: String = ""
    var commitDescription: String = ""
    var isCommitting: Bool = false
    
    func pickRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Repository"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        repositoryURL = url
        selectedChangeID = nil
        Task { await refreshStatus()}
    }
    
    func refreshStatus() async {
            guard let repositoryURL else { return }
            do {
                changes = try await gitService.status(at: repositoryURL)
                currentBranch = try? await gitService.currentBranch(at: repositoryURL)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    
    func loadDiff() async {
            guard let repositoryURL, let selectedChange else {
                currentDiff = nil
                return
            }
            isLoadingDiff = true
            defer { isLoadingDiff = false }
            do {
                currentDiff = try await gitService.diff(at: repositoryURL, for: selectedChange)
                errorMessage = nil
            } catch {
                currentDiff = nil
                errorMessage = error.localizedDescription
            }
        }
    
    func toggleStage(for change: FileChange) async {
        guard let repositoryURL else { return }
        do {
            if change.isStaged {
                try await gitService.unstage(at: repositoryURL, path: change.path)
            }else{
                try await gitService.stage(at: repositoryURL, path: change.path)
            }
            await refreshStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func commit() async {
        guard let repositoryURL, !commitSummary.isEmpty else { return }
        
        isCommitting = true
        defer { isCommitting = false}
        do {
            try await gitService.commit(at: repositoryURL, summary: commitSummary, description: commitDescription.isEmpty ? nil : commitDescription)
            commitSummary = ""
            commitDescription = ""
            selectedChangeID = nil
            currentDiff = nil
            await refreshStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func setAllStaged(_ staged: Bool) async {
        guard let repositoryURL else { return }
        do {
            for change in changes {
                if staged {
                    try await gitService.stage(at: repositoryURL, path: change.path)
                } else {
                    try await gitService.unstage(at: repositoryURL, path: change.path)
                }
            }
            await refreshStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
}
