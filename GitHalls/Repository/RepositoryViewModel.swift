//
//  RepositoryViewModel.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//
import AppKit
import Foundation
import Observation

enum SidebarMode: Hashable {
    case changes, history
}

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
    
    var recentRepositoryURLs: [URL] = RecentRepositoriesStore.load()
    
    var sidebarMode: SidebarMode = .changes
    var commits: [Commit] = []
    var selectedCommitID: Commit.ID?
    
    var selectedCommitDetail: CommitDetail?
    var isLoadingCommitDetail = false
    
    var pendingDiscard: FileChange?

    // Tokens de "esta é a chamada mais recente?" — evita que uma resposta assíncrona
    // atrasada (repo/arquivo/commit trocado enquanto a chamada anterior ainda estava
    // em voo) sobrescreva o estado com dado desatualizado.
    private var statusRequestToken = UUID()
    private var diffRequestToken = UUID()
    private var commitDetailRequestToken = UUID()

    func requestDiscard(_ change: FileChange) {
        pendingDiscard = change
    }

    func cancelDiscard() {
        pendingDiscard = nil
    }
    
    func pickRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Repository"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }
    
    
    func refreshStatus() async {
            guard let repositoryURL else { return }
            let token = UUID()
            statusRequestToken = token
            do {
                let newChanges = try await gitService.status(at: repositoryURL)
                let branch = try? await gitService.currentBranch(at: repositoryURL)
                // Uma chamada mais nova (outro repo aberto, refresh disparado de novo) já rodou
                // enquanto esta esperava o git — descarta este resultado desatualizado.
                guard statusRequestToken == token else { return }
                changes = newChanges
                currentBranch = branch
                errorMessage = nil
            } catch {
                guard statusRequestToken == token else { return }
                errorMessage = error.localizedDescription
            }
        }

    func loadDiff() async {
            guard let repositoryURL, let selectedChange else {
                currentDiff = nil
                return
            }
            let token = UUID()
            diffRequestToken = token
            isLoadingDiff = true
            defer { if diffRequestToken == token { isLoadingDiff = false } }
            do {
                let diff = try await gitService.diff(at: repositoryURL, for: selectedChange)
                // O usuário já selecionou outro arquivo enquanto este diff carregava — ignora.
                guard diffRequestToken == token else { return }
                currentDiff = diff
                errorMessage = nil
            } catch {
                guard diffRequestToken == token else { return }
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
    
    

    func open(_ url: URL) {
        repositoryURL = url
        selectedChangeID = nil
        currentDiff = nil
        commits = []
        selectedCommitID = nil
        selectedCommitDetail = nil
        isLoadingCommitDetail = false
        pendingDiscard = nil
        RecentRepositoriesStore.addOrPromote(url)
        recentRepositoryURLs = RecentRepositoriesStore.load()
        Task { await refreshStatus() }
    }

    func openMostRecentRepositoryIfNeeded() {
        guard repositoryURL == nil, let mostRecent = recentRepositoryURLs.first else { return }
        open(mostRecent)
    }
    
    func closeRepository() {
        repositoryURL = nil
        changes = []
        selectedChangeID = nil
        currentDiff = nil
        currentBranch = nil
        commitSummary = ""
        commitDescription = ""
        errorMessage = nil
        commits = []
        selectedCommitID = nil
        selectedCommitDetail = nil
        isLoadingCommitDetail = false
        pendingDiscard = nil
    }

    func forgetRecent(_ url: URL) {
        RecentRepositoriesStore.remove(url)
        recentRepositoryURLs = RecentRepositoriesStore.load()
    }
    
    func loadCommits() async {
        guard let repositoryURL else { return }
        do {
            commits = try await gitService.log(at: repositoryURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func loadCommitDetail() async {
        guard let repositoryURL, let hash = selectedCommitID,
              let commit = commits.first(where: { $0.id == hash }) else {
            selectedCommitDetail = nil
            return
        }
        let token = UUID()
        commitDetailRequestToken = token
        isLoadingCommitDetail = true
        defer { if commitDetailRequestToken == token { isLoadingCommitDetail = false } }
        do {
            let paths = try await gitService.changedPaths(at: repositoryURL, hash: hash)
            var diffs: [FileDiff] = []
            for path in paths {
                diffs.append(try await gitService.commitFileDiff(at: repositoryURL, hash: hash, path: path))
            }
            // O usuário já selecionou outro commit (ou fechou/trocou de repo) enquanto isso carregava.
            guard commitDetailRequestToken == token else { return }
            selectedCommitDetail = CommitDetail(commit: commit, fileDiffs: diffs)
            errorMessage = nil
        } catch {
            guard commitDetailRequestToken == token else { return }
            selectedCommitDetail = nil
            errorMessage = error.localizedDescription
        }
    }

    func confirmDiscard(_ change: FileChange) async {
        guard let repositoryURL else {
            pendingDiscard = nil
            return
        }
        // Revalida contra o status atual antes de uma ação destrutiva — o arquivo pode ter
        // mudado de estado no tempo entre o clique direito e a confirmação do diálogo.
        await refreshStatus()
        guard let currentChange = changes.first(where: { $0.path == change.path }) else {
            pendingDiscard = nil
            return
        }
        do {
            try await gitService.discard(at: repositoryURL, change: currentChange)
            if selectedChangeID == currentChange.id {
                selectedChangeID = nil
                currentDiff = nil
            }
            await refreshStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingDiscard = nil
    }
}

