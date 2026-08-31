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
    case changes, history, kanban
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

    var isStaging = false
    
    // Tokens de "esta é a chamada mais recente?" — evita que uma resposta assíncrona
    // atrasada (repo/arquivo/commit trocado enquanto a chamada anterior ainda estava
    // em voo) sobrescreva o estado com dado desatualizado.
    private var statusRequestToken = UUID()
    private var diffRequestToken = UUID()
    private var commitDetailRequestToken = UUID()
    
    var branches: [Branch] = []
    var isSwitchingBranch = false

    func requestDiscard(_ change: FileChange) {
        pendingDiscard = change
    }

    func cancelDiscard() {
        pendingDiscard = nil
    }
    
    var syncAhead = 0
    var syncBehind = 0
    var hasUpstream = false
    var isFetching = false
    var isPulling = false
    var isPushing = false
    
    var isMerging = false
    
    var isCloning = false

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
            let sync = try? await gitService.branchSync(at: repositoryURL)
            guard statusRequestToken == token else { return }
            changes = newChanges
            currentBranch = branch
            if let sync {
                syncAhead = sync.ahead
                syncBehind = sync.behind
                hasUpstream = true
            } else {
                syncAhead = 0
                syncBehind = 0
                hasUpstream = false
            }
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
    
    func toggleStage(for change: FileChange) async {
        guard let repositoryURL else { return }
        isStaging = true
        defer { isStaging = false }
        do {
            if change.isStaged {
                try await gitService.unstage(at: repositoryURL, path: change.path)
            } else {
                try await gitService.stage(at: repositoryURL, path: change.path)
            }
            await refreshStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setAllStaged(_ staged: Bool) async {
        guard let repositoryURL else { return }
        isStaging = true
        defer { isStaging = false }
        do {
            let paths = changes.map(\.path)
            if staged {
                try await gitService.stage(at: repositoryURL, paths: paths)
            } else {
                try await gitService.unstage(at: repositoryURL, paths: paths)
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
    
    func loadBranches() async {
        guard let repositoryURL else { return }
        do {
            branches = try await gitService.branches(at: repositoryURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func switchBranch(to name: String) async {
        guard let repositoryURL else { return }
        isSwitchingBranch = true
        defer { isSwitchingBranch = false }
        do {
            try await gitService.switchBranch(at: repositoryURL, name: name)
            selectedChangeID = nil
            currentDiff = nil
            selectedCommitID = nil
            selectedCommitDetail = nil
            await refreshStatus()
            await loadCommits()
            await loadBranches()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createBranch(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let repositoryURL, !trimmed.isEmpty else { return }
        isSwitchingBranch = true
        defer { isSwitchingBranch = false }
        do {
            try await gitService.createBranch(at: repositoryURL, name: trimmed)
            selectedChangeID = nil
            currentDiff = nil
            selectedCommitID = nil
            selectedCommitDetail = nil
            await refreshStatus()
            await loadCommits()
            await loadBranches()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func fetch() async {
        guard let repositoryURL else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            try await gitService.fetch(at: repositoryURL)
            await refreshStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pull() async {
        guard let repositoryURL else { return }
        isPulling = true
        defer { isPulling = false }
        do {
            try await gitService.pull(at: repositoryURL)
            selectedChangeID = nil
            currentDiff = nil
            await refreshStatus()
            await loadCommits()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func push() async {
        guard let repositoryURL, let branch = currentBranch else { return }
        isPushing = true
        defer { isPushing = false }
        do {
            try await gitService.push(at: repositoryURL, branch: branch)
            await refreshStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func merge(branch: String) async {
        guard let repositoryURL else { return }
        isMerging = true
        defer { isMerging = false }
        do {
            try await gitService.merge(at: repositoryURL, branch: branch)
            selectedChangeID = nil
            currentDiff = nil
            await refreshStatus()
            await loadCommits()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            await refreshStatus()
        }
    }
    
    func clone(url: String, into destinationURL: URL) async {
        isCloning = true
        defer { isCloning = false }
        do {
            try await gitService.clone(url: url, into: destinationURL)
            open(destinationURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

