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
    case changes, history, kanban, graph
}

@Observable
@MainActor
final class RepositoryViewModel {
    private let gitService = GitService()
    private let gitHubService = GitHubService()

    var isCreatingPullRequest = false

    init() {
        startPeriodicRefresh()
    }

    private func startPeriodicRefresh() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                await self?.refreshStatus()
            }
        }
    }

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
    
    var recentBranchNames: [String] = []
    
    private var statusRequestToken = UUID()
    private var diffRequestToken = UUID()
    private var commitDetailRequestToken = UUID()
    
    var branches: [Branch] = []
    var isSwitchingBranch = false

    var graphRows: [GraphRow] = []

    /// Fixed for the whole list, so the text columns line up on every row.
    var graphLaneCount = 1
    var isLoadingGraph = false

    /// Serialises the branch operations the graph's context menu offers, so two
    /// clicks cannot race each other into the same repository.
    var isMutatingBranch = false

    private var graphRequestToken = UUID()

    /// How far back the graph reads. See `loadGraph` before raising it.
    private let graphCommitLimit = 1000

    /// Set when `branch -d` was refused because the branch is not fully merged.
    /// Turns the error alert into an offer, exactly like
    /// `pullBlockedByLocalChanges`.
    var pendingForceDeleteBranch: String?

    /// Awaiting the confirmation dialog. Deleting a remote branch has no undo
    /// and affects everyone else on it.
    var pendingRemoteBranchDeletion: String?

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

    /// git refused a pull because it would have written over uncommitted work.
    /// The error alert turns this into an offer rather than a dead end.
    var pullBlockedByLocalChanges = false

    /// The repository's README, as blocks to lay out.
    ///
    /// Read from the working tree, so it is always this branch's own copy:
    /// checking out another branch rewrites the file on disk, and this re-reads
    /// it.
    private(set) var readme: [MarkdownBlock] = []

    private(set) var readmeFileName: String?

    /// Repository and branch the README on screen was read for. A status
    /// refresh happens on every window activation, and re-reading a file that
    /// cannot have changed is work for nothing.
    private var readmeKey: String?
    
    var isMerging = false

    var isCloning = false

    var currentIdentity: GitIdentity?
    var hasLocalIdentityOverride = false
    var savedIdentities: [GitIdentity] = GitIdentityStore.load()
    var isSwitchingIdentity = false

    func reloadSavedIdentities() {
        savedIdentities = GitIdentityStore.load()
    }

    func setIdentity(_ identity: GitIdentity, fixRemoteURL: Bool) async {
        guard let repositoryURL, !isSwitchingIdentity else { return }
        isSwitchingIdentity = true
        defer { isSwitchingIdentity = false }
        do {
            try await gitService.setIdentity(at: repositoryURL, name: identity.name, email: identity.email)
            if fixRemoteURL, !identity.githubUsername.isEmpty {
                try? await gitService.setRemoteUsername(at: repositoryURL, username: identity.githubUsername)
            }
            await refreshStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Guarda usuário+token no credential helper do git (normalmente
    /// osxkeychain) — não fica salvo em lugar nenhum do GitHalls. Corrige o
    /// caso em que essa conta nunca autenticou por HTTPS nessa máquina, então
    /// o git não tem credencial pra resolver e o push/pull falha sem TTY pra
    /// perguntar.
    func saveGitHubToken(_ token: String, forUsername username: String) async -> Bool {
        guard !token.isEmpty, !username.isEmpty else { return false }
        do {
            try await gitService.approveCredential(username: username, token: token)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
            let sync = try? await gitService.branchSync(at: repositoryURL)
            let identity = try? await gitService.identity(at: repositoryURL)
            let hasLocal = (try? await gitService.hasLocalIdentity(at: repositoryURL)) ?? false
            guard statusRequestToken == token else { return }
            changes = newChanges
            currentBranch = branch
            await loadReadmeIfNeeded(at: repositoryURL, branch: branch)
            currentIdentity = identity
            hasLocalIdentityOverride = hasLocal
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
    
    /// The bytes behind a binary file, for the preview that stands in for its
    /// diff. A nil revision means the working tree — the side no revision names.
    ///
    /// Loaded by the view that shows it rather than here: a commit can carry
    /// twenty images, and only the one on screen is worth a process.
    func fileBytes(path: String, revision: String?) async -> Data? {
        guard let repositoryURL else { return nil }

        guard let revision else {
            return await gitService.workingTreeBlob(at: repositoryURL, path: path)
        }

        return try? await gitService.blob(at: repositoryURL, revision: revision, path: path)
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
        guard let repositoryURL, !isStaging else { return }
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
        guard let repositoryURL, !isStaging else { return }
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
        clearGraphState()
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
        readme = []
        readmeFileName = nil
        readmeKey = nil
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
        clearGraphState()
        currentIdentity = nil
        hasLocalIdentityOverride = false
    }

    private func clearGraphState() {
        graphRows = []
        graphLaneCount = 1
        isLoadingGraph = false
        pendingForceDeleteBranch = nil
        pendingRemoteBranchDeletion = nil
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
    
    func loadGraph() async {
        guard let repositoryURL else { return }
        let token = UUID()
        graphRequestToken = token
        isLoadingGraph = true
        defer { if graphRequestToken == token { isLoadingGraph = false } }
        do {
            let commits = try await gitService.graphLog(at: repositoryURL, limit: graphCommitLimit)
            // O(rows x lanes) — about ten thousand integer comparisons at the
            // current limit, well inside a frame. If `graphCommitLimit` ever
            // grows past a few thousand, wrap this in
            // `await Task.detached { CommitGraphBuilder.build(commits) }.value`:
            // the builder is a pure enum over Sendable values, so that is the
            // whole change.
            let graph = CommitGraphBuilder.build(commits)
            // A branch switch or another refresh landed while this was loading.
            guard graphRequestToken == token else { return }
            graphRows = graph.rows
            graphLaneCount = graph.laneCount
            errorMessage = nil
        } catch {
            guard graphRequestToken == token else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// What every branch operation does afterwards: the working tree, the graph
    /// and the branch list can all have moved.
    private func reloadAfterBranchChange() async {
        await refreshStatus()
        await loadCommits()
        await loadGraph()
        await loadBranches()
    }

    /// Runs a branch operation, then reloads. Every context-menu action funnels
    /// through here so none of them can forget the reload or the error alert.
    private func performBranchOperation(_ operation: () async throws -> Void) async {
        guard !isMutatingBranch else { return }
        isMutatingBranch = true
        defer { isMutatingBranch = false }
        do {
            try await operation()
            await reloadAfterBranchChange()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            await reloadAfterBranchChange()
        }
    }

    func checkoutCommit(_ hash: String) async {
        guard let repositoryURL else { return }
        await performBranchOperation {
            try await gitService.checkoutCommit(at: repositoryURL, hash: hash)
        }
    }

    func createBranch(named name: String, from startPoint: String, switchTo: Bool) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let repositoryURL, !trimmed.isEmpty else { return }
        await performBranchOperation {
            try await gitService.createBranch(
                at: repositoryURL, name: trimmed, startPoint: startPoint, switchTo: switchTo
            )
            RecentBranchesStore.addOrPromote(trimmed, for: repositoryURL)
        }
        recentBranchNames = RecentBranchesStore.load(for: repositoryURL)
    }

    func renameBranch(_ oldName: String, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard let repositoryURL, !trimmed.isEmpty, trimmed != oldName else { return }
        await performBranchOperation {
            try await gitService.renameBranch(at: repositoryURL, from: oldName, to: trimmed)
            RecentBranchesStore.addOrPromote(trimmed, for: repositoryURL)
        }
        recentBranchNames = RecentBranchesStore.load(for: repositoryURL)
    }

    func deleteLocalBranch(named name: String, force: Bool = false) async {
        guard let repositoryURL, !isMutatingBranch else { return }
        isMutatingBranch = true
        defer { isMutatingBranch = false }
        pendingForceDeleteBranch = nil
        do {
            try await gitService.deleteLocalBranch(at: repositoryURL, name: name, force: force)
            await reloadAfterBranchChange()
            errorMessage = nil
        } catch {
            // Not a dead end. The commits are still there, and the user may well
            // want them gone — so say what git said, then offer the escalation.
            if !force, case GitError.commandFailed(_, let message) = error,
               BranchDeleteDiagnostics.isUnmerged(message) {
                pendingForceDeleteBranch = name
            }
            errorMessage = error.localizedDescription
            await reloadAfterBranchChange()
        }
    }

    func requestRemoteBranchDeletion(_ name: String) {
        pendingRemoteBranchDeletion = name
    }

    func cancelRemoteBranchDeletion() {
        pendingRemoteBranchDeletion = nil
    }

    func confirmRemoteBranchDeletion() async {
        guard let repositoryURL, let remoteBranch = pendingRemoteBranchDeletion else { return }
        pendingRemoteBranchDeletion = nil
        // "origin/feature" names the remote and the branch on it.
        let remote = remoteBranch.contains("/")
            ? String(remoteBranch[..<remoteBranch.firstIndex(of: "/")!])
            : "origin"
        let branch = Branch.remoteShortName(from: remoteBranch)
        await performBranchOperation {
            try await gitService.deleteRemoteBranch(at: repositoryURL, remote: remote, name: branch)
        }
    }

    func pushBranch(_ name: String, setUpstream: Bool) async {
        guard let repositoryURL else { return }
        await performBranchOperation {
            try await gitService.pushBranch(at: repositoryURL, branch: name, setUpstream: setUpstream)
        }
    }

    /// Updates a branch that is not checked out. `pull` is the right call for
    /// the current branch; this refspec is the only one that moves another.
    func fastForwardBranch(_ name: String) async {
        guard let repositoryURL else { return }
        await performBranchOperation {
            try await gitService.fastForwardBranch(at: repositoryURL, branch: name)
        }
    }

    func setUpstream(of branch: String, to upstream: String) async {
        let trimmed = upstream.trimmingCharacters(in: .whitespaces)
        guard let repositoryURL, !trimmed.isEmpty else { return }
        await performBranchOperation {
            try await gitService.setUpstream(at: repositoryURL, branch: branch, upstream: trimmed)
        }
    }

    func upstream(of branch: String) async -> String? {
        guard let repositoryURL else { return nil }
        return try? await gitService.upstream(at: repositoryURL, branch: branch)
    }

    func copyCommitMessage(_ hash: String) async {
        guard let repositoryURL else { return }
        do {
            let message = try await gitService.commitMessage(at: repositoryURL, hash: hash)
            QuickActions.copyToClipboard(message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadCommitDetail() async {
        // `commits` is History mode's list, which only covers the current
        // branch. A commit picked out of the graph can belong to any branch, so
        // fall back to the graph's own rows before giving up.
        guard let repositoryURL, let hash = selectedCommitID,
              let commit = commits.first(where: { $0.id == hash })
                ?? graphRows.first(where: { $0.commit.hash == hash })?.commit.commit else {
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
            recentBranchNames = RecentBranchesStore.load(for: repositoryURL)
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
            RecentBranchesStore.addOrPromote(name, for: repositoryURL)
            recentBranchNames = RecentBranchesStore.load(for: repositoryURL)
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
            RecentBranchesStore.addOrPromote(trimmed, for: repositoryURL)
            recentBranchNames = RecentBranchesStore.load(for: repositoryURL)
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
            pullBlockedByLocalChanges = Self.isBlockedByLocalChanges(error)
            errorMessage = error.localizedDescription
        }
    }

    /// The offer a blocked pull turns into: set the changes aside, pull, put
    /// them back.
    func pullStashingLocalChanges() async {
        guard let repositoryURL else { return }
        isPulling = true
        pullBlockedByLocalChanges = false
        defer { isPulling = false }

        do {
            let conflicted = try await gitService.pullAutostash(at: repositoryURL)
            selectedChangeID = nil
            currentDiff = nil
            await refreshStatus()
            await loadCommits()

            // Not an error — the pull worked. But saying nothing would leave the
            // user in a conflicted tree with a stash nobody mentioned.
            errorMessage = conflicted ? "Pulled, but your local changes could not be put back cleanly.\n\nThey are safe in the stash: resolve the conflicts in the affected files, then drop the leftover stash entry." : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Readme

    /// Longest README worth laying out. Past this it is a data file that
    /// happens to be called README, and rendering it would only hang the pane.
    private static let readmeSizeLimit = 512 * 1024

    private func loadReadmeIfNeeded(at repoURL: URL, branch: String?) async {
        let key = "\(repoURL.path)#\(branch ?? "")"
        guard readmeKey != key else { return }
        readmeKey = key

        guard let name = ReadmeFinder.pick(from: (try? FileManager.default.contentsOfDirectory(atPath: repoURL.path)) ?? []),
              let data = try? Data(contentsOf: repoURL.appending(path: name)),
              data.count <= Self.readmeSizeLimit,
              let text = String(data: data, encoding: .utf8)
        else {
            readme = []
            readmeFileName = nil
            return
        }

        readmeFileName = name
        readme = MarkdownParser.parse(text)
    }

    // MARK: - Conflicts

    /// Files git could not merge on its own. Nothing else can be committed
    /// until these are dealt with, so they are worth calling out separately
    /// rather than leaving in the list looking like ordinary changes.
    var conflictedChanges: [FileChange] {
        changes.filter { $0.status == .unmerged }
    }

    var hasConflicts: Bool { !conflictedChanges.isEmpty }

    /// Tells git the file is settled. Resolving *is* staging — there is no
    /// separate "resolved" state, which is why this reuses stage.
    func markResolved(_ change: FileChange) async {
        guard let repositoryURL else { return }

        isStaging = true
        defer { isStaging = false }

        do {
            try await gitService.stage(at: repositoryURL, path: change.path)
            await refreshStatus()
            await loadDiff()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ change: FileChange, in editor: ExternalEditor) {
        guard let repositoryURL else { return }

        ExternalEditors.open(repositoryURL.appending(path: change.path), with: editor)
    }

    /// Clears the alert and the offer it was carrying.
    func dismissError() {
        errorMessage = nil
        pullBlockedByLocalChanges = false
        pendingForceDeleteBranch = nil
    }

    private static func isBlockedByLocalChanges(_ error: Error) -> Bool {
        guard case GitError.commandFailed(_, let message) = error else { return false }

        return PullDiagnostics.isBlockedByLocalChanges(message)
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
            // The ahead/behind counts are only as fresh as the last fetch, so a
            // push can be the first thing to learn the remote moved. Fetch
            // before giving up: the refresh turns the button into the sync that
            // will actually work.
            if Self.isRejectedForNewRemoteWork(error) {
                try? await gitService.fetch(at: repositoryURL)
            }
            await refreshStatus()
            errorMessage = error.localizedDescription
        }
    }

    /// The one action the sync button performs, chosen from the current state.
    func sync() async {
        pullBlockedByLocalChanges = false

        switch BranchSync.action(hasUpstream: hasUpstream, ahead: syncAhead, behind: syncBehind) {
        case .upToDate:
            return
        case .publish, .push:
            await push()
        case .pull:
            await pull()
        case .pullThenPush:
            await pullThenPush()
        }
    }

    /// A diverged branch pulls before it pushes. Both in one action so a merge
    /// that stops on a conflict stops the push with it.
    private func pullThenPush() async {
        guard let repositoryURL, let branch = currentBranch else { return }
        isPulling = true
        isPushing = true
        defer {
            isPulling = false
            isPushing = false
        }

        selectedChangeID = nil
        currentDiff = nil

        do {
            try await gitService.pullDivergent(at: repositoryURL)
            try await gitService.push(at: repositoryURL, branch: branch)
            errorMessage = nil
        } catch {
            // Same offer as a plain pull: the sync button is where this is most
            // often hit.
            pullBlockedByLocalChanges = Self.isBlockedByLocalChanges(error)
            errorMessage = error.localizedDescription
        }

        // Either way: a merge that conflicted left the working tree changed, and
        // that is exactly what the user needs to see.
        await refreshStatus()
        await loadCommits()
    }

    /// A push git refused because the upstream has commits this clone has never
    /// seen — the one rejection a fetch changes the answer to.
    private static func isRejectedForNewRemoteWork(_ error: Error) -> Bool {
        guard case GitError.commandFailed(_, let message) = error else { return false }

        let lowered = message.lowercased()
        return lowered.contains("fetch first") || lowered.contains("non-fast-forward")
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
    
    func suggestedCommitType() async -> ConventionalCommitType {
        let staged = changes.filter(\.isStaged)
        guard let repositoryURL else {
            return ConventionalCommitSuggester.suggestedType(for: staged)
        }
        let numstat = (try? await gitService.numstat(at: repositoryURL)) ?? [:]
        return ConventionalCommitSuggester.suggestedType(for: staged, numstat: numstat)
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

    func createPullRequest(title: String, description: String, base: String?) async {
        guard let repositoryURL else { return }
        isCreatingPullRequest = true
        defer { isCreatingPullRequest = false }
        do {
            if let branch = currentBranch {
                try await gitService.push(at: repositoryURL, branch: branch)
            }

            if await gitHubService.isAvailable() {
                let output = try await gitHubService.createPullRequest(
                    at: repositoryURL, title: title, body: description, base: base
                )
                if let url = URL(string: output) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                let remote = try await gitService.remoteURL(at: repositoryURL)
                guard let (owner, repo) = GitHubService.ownerAndRepo(fromRemoteURL: remote) else {
                    throw GitError.invalidRemoteURL
                }
                guard let url = GitHubService.pullRequestBrowserURL(
                    owner: owner, repo: repo,
                    head: currentBranch ?? "HEAD", base: base,
                    title: title, body: description
                ) else {
                    throw GitError.invalidRemoteURL
                }
                NSWorkspace.shared.open(url)
            }

            await refreshStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

