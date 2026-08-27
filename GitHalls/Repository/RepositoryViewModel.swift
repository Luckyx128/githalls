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
}
