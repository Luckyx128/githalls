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

    /// Which half of the selected file the diff shows. Only a partly staged
    /// file has two; the sidebar sets it with the row that was clicked.
    var selectedDiffSide: DiffSide = .unstaged

    /// Lines picked in the diff gutter. Owned here, not by the view, so a
    /// reload or an action can clear it without the view's help.
    let diffSelection = DiffSelection()

    /// A line or hunk discard waiting for its confirmation. The patch is built
    /// when it is asked for, so the dialog and the action agree on what goes.
    var pendingLineDiscard: PendingLineDiscard?

    private var loadedDiffKey: String?

    static let ignoreWhitespaceKey = "diff.ignoreWhitespace"

    /// Show the diff with `-w`. Persisted; flipping it reloads the diff. While
    /// on, partial staging is off: a patch cannot be made from a diff that
    /// pretends blank changes are not there.
    var ignoreWhitespace: Bool = UserDefaults.standard.bool(forKey: RepositoryViewModel.ignoreWhitespaceKey) {
        didSet {
            guard ignoreWhitespace != oldValue else { return }
            UserDefaults.standard.set(ignoreWhitespace, forKey: Self.ignoreWhitespaceKey)
            diffSelection.clear()
            Task { await loadDiff() }
        }
    }

    /// Whitespace is hidden, and so the staging this file would otherwise offer is off.
    var isStagingBlockedByWhitespace: Bool {
        guard ignoreWhitespace, let change = selectedChange, let diff = currentDiff else { return false }
        return change.status != .untracked && diff.partialMode(for: change, side: selectedDiffSide) != nil
    }

    // MARK: Expandable context

    /// The new side of the file on screen, line by line, for the rows between hunks.
    private var contextSource: [String]?
    private var contextExpansion = ContextExpansion()
    private var contextGeneration = 0
    @ObservationIgnored private var displayCache: (key: String, diff: FileDiff)?
    private static let contextSourceByteLimit = 4_000_000

    /// The diff as shown: the real one plus any context the reader opened and
    /// the rows that open more. Never what staging reads — that is `currentDiff`.
    func displayDiff(for diff: FileDiff) -> FileDiff {
        guard contextSource != nil else { return diff }
        let key = "\(contextGeneration)|\(diff.path)|\(diff.lines.count)"
        if let displayCache, displayCache.key == key { return displayCache.diff }
        let built = ContextExpander.display(diff: diff, source: contextSource, expansion: contextExpansion)
        displayCache = (key, built)
        return built
    }

    func expandContext(gap: Int, _ direction: ExpanderRow.Direction) {
        contextExpansion.reveal(gap: gap, direction)
        contextGeneration += 1
        diffSelection.anchor = nil
    }

    private func resetContext(source: [String]?) {
        contextSource = source
        contextExpansion = ContextExpansion()
        contextGeneration += 1
    }

    /// Reads the file from where the new side of this diff lives: the working
    /// tree for the unstaged half, the index for the staged one.
    private func loadContextSource(for change: FileChange, side: DiffSide, diff: FileDiff) async -> [String]? {
        guard !diff.isBinary, !diff.isNewFile, !diff.isDeletedFile, diff.hunkCount > 0,
              change.status != .untracked, let repositoryURL
        else { return nil }

        let data: Data?
        if side == .staged, change.status != .unmerged {
            data = try? await gitService.blob(at: repositoryURL, revision: "", path: change.path)
        } else {
            let url = repositoryURL.appending(path: change.path)
            data = await Task.detached { try? Data(contentsOf: url) }.value
        }
        guard let data, data.count <= Self.contextSourceByteLimit,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return FileDiff.sourceLines(of: text)
    }

    var selectedChange: FileChange? {
        changes.first { $0.id == selectedChangeID }
    }
    
    var allStaged: Bool {
        !changes.isEmpty && changes.allSatisfy { $0.isStaged }
    }
    
    var currentBranch: String?

    /// The Jira issues the checked-out branch belongs to, once Jira has said
    /// the keys are real. Set by `IssueLinkCoordinator`; the next commit names them.
    var linkedIssueKeys: [String] = []

    /// Told after a push lands, with the commits it sent; and after a pull
    /// request is opened, with its branch. The repository knows nothing about
    /// Jira — whoever listens decides what a push means for an issue.
    @ObservationIgnored var onPush: ((PushedWork) -> Void)?
    @ObservationIgnored var onPullRequestCreated: ((_ branch: String) -> Void)?

    var commitSummary: String = ""
    var commitDescription: String = ""
    var isCommitting: Bool = false

    /// People credited with `Co-authored-by:` on the next commit.
    var commitCoAuthors: [CoAuthor] = []

    /// People from the repository's history, offered as co-author suggestions.
    var knownAuthors: [CoAuthor] = []

    /// The next commit rewrites HEAD instead of adding one.
    var isAmending = false

    var headCommit: HeadCommit?
    private var knownAuthorsRequestToken = UUID()

    /// Undo and amend rewrite history, so they apply only to a local, ordinary
    /// commit, and never while a merge is waiting to be finished.
    var canRewriteHead: Bool {
        (headCommit?.isRewritable ?? false) && mergeState == nil
    }
    
    var recentRepositoryURLs: [URL] = RecentRepositoriesStore.load()
    
    var sidebarMode: SidebarMode = .changes
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
    /// Row label per `Branch.id` ("you" or a name); branches with no guess are absent.
    var branchCreatorLabels: [String: String] = [:]
    /// Keyed by tip + base hash, so reopening the popover costs no git runs and
    /// a branch is only looked at again once it or the default branch moves.
    /// An empty string records "looked, nobody to name".
    private var creatorCache: [String: String] = [:]
    var isSwitchingBranch = false

    var graphRows: [GraphRow] = []

    /// Whether the history list draws every branch or only what HEAD reaches.
    var graphShowsAllBranches: Bool = UserDefaults.standard.object(forKey: "historyAllBranches") as? Bool ?? true {
        didSet { UserDefaults.standard.set(graphShowsAllBranches, forKey: "historyAllBranches") }
    }

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

    /// Commits a push would send, for the marker beside their hash.
    var unpushedCommitHashes: Set<String> = []
    var syncBehind = 0
    var hasUpstream = false
    var isFetching = false

    /// When the last fetch succeeded, manual or automatic.
    var lastFetchDate: Date?

    /// Why the last background fetch failed, for a tooltip. Never an alert: a
    /// laptop on a train should not nag every five minutes.
    var lastFetchError: String?

    private var autoFetchTask: Task<Void, Never>?
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
    var isReverting = false

    /// The merge git left open, if any. Nil the rest of the time.
    var mergeState: MergeState?
    var isFinalizingMerge = false

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
            let merge = try? await gitService.mergeState(at: repositoryURL)
            let head = await gitService.headCommit(at: repositoryURL)
            guard statusRequestToken == token else { return }
            mergeState = merge
            headCommit = head
            if head == nil || !(head!.isRewritable) { isAmending = false }
            changes = newChanges
            reconcileDiffSide()
            currentBranch = branch
            await loadReadmeIfNeeded(at: repositoryURL, branch: branch)
            currentIdentity = identity
            hasLocalIdentityOverride = hasLocal
            if let sync {
                // A push or commit moves this count; the marker follows it.
                if syncAhead != sync.ahead {
                    unpushedCommitHashes = await gitService.unpushedCommitHashes(at: repositoryURL)
                }
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
                loadedDiffKey = nil
                return
            }
            let token = UUID()
            diffRequestToken = token
            isLoadingDiff = true
            defer { if diffRequestToken == token { isLoadingDiff = false } }
            let side = selectedDiffSide
            let change = selectedChange
            let ignoringWhitespace = ignoreWhitespace
            do {
                let diff = try await gitService.diff(at: repositoryURL, for: change, side: side,
                                                     ignoreWhitespace: ignoringWhitespace)
                // O usuário já selecionou outro arquivo enquanto este diff carregava — ignora.
                guard diffRequestToken == token else { return }

                // A reload that finds the same text (window activation, a status
                // refresh) must not rebuild the view or drop the selection on it.
                let key = "\(change.id)|\(side)|\(ignoringWhitespace)"
                if currentDiff == nil || loadedDiffKey != key || !currentDiff!.hasSameContent(as: diff) {
                    let source = await loadContextSource(for: change, side: side, diff: diff)
                    guard diffRequestToken == token else { return }
                    diffSelection.clear()
                    // Opened context belongs to the stretches of this very diff:
                    // once the hunks change, the numbers no longer mean the same gaps.
                    resetContext(source: source)
                    currentDiff = diff
                }
                loadedDiffKey = key
                errorMessage = nil
            } catch {
                guard diffRequestToken == token else { return }
                currentDiff = nil
                loadedDiffKey = nil
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
        let amend = isAmending && canRewriteHead

        isCommitting = true
        defer { isCommitting = false}
        do {
            let message = CommitMessageComposer.compose(
                summary: commitSummary,
                description: commitDescription,
                coAuthors: commitCoAuthors,
                issueKeys: linkedIssueKeys
            )
            try await gitService.commit(at: repositoryURL, summary: message.summary, description: message.body, amend: amend)
            commitSummary = ""
            commitDescription = ""
            commitCoAuthors = []
            isAmending = false
            selectedChangeID = nil
            currentDiff = nil
            await refreshStatus()
            await loadGraph()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Turning amend on loads HEAD's message into empty fields, so the common
    /// "fix the wording" case needs no retyping; fields already typed are kept.
    func setAmending(_ enabled: Bool) async {
        guard let repositoryURL else { return }
        guard enabled else {
            isAmending = false
            return
        }
        guard canRewriteHead, let head = headCommit else { return }
        isAmending = true
        guard commitSummary.isEmpty, commitDescription.isEmpty, commitCoAuthors.isEmpty else { return }
        do {
            let parts = CommitMessageComposer.split(try await gitService.commitMessage(at: repositoryURL, hash: head.hash))
            guard isAmending, commitSummary.isEmpty else { return }
            commitSummary = parts.summary
            commitDescription = parts.description
            commitCoAuthors = parts.coAuthors
        } catch {
            isAmending = false
            errorMessage = error.localizedDescription
        }
    }

    /// `git reset --soft HEAD~1`, then the message goes back in the form, as in
    /// GitHub Desktop: the changes stay staged and nothing needs retyping.
    func undoLastCommit() async {
        guard let repositoryURL, canRewriteHead, let head = headCommit, !isCommitting else { return }

        isCommitting = true
        defer { isCommitting = false }
        do {
            let message = try await gitService.commitMessage(at: repositoryURL, hash: head.hash)
            try await gitService.undoLastCommit(at: repositoryURL)
            let parts = CommitMessageComposer.split(message)
            commitSummary = parts.summary
            commitDescription = parts.description
            commitCoAuthors = parts.coAuthors
            isAmending = false
            await refreshStatus()
            await loadGraph()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Adds `Name <email>`; false when the text is not in that form.
    @discardableResult
    func addCoAuthor(_ text: String) -> Bool {
        guard let author = CoAuthor.parse(text) else { return false }
        if !commitCoAuthors.contains(author) { commitCoAuthors.append(author) }
        return true
    }

    func removeCoAuthor(_ author: CoAuthor) {
        commitCoAuthors.removeAll { $0 == author }
    }

    func loadKnownAuthors() async {
        guard let repositoryURL else { return }
        let token = UUID()
        knownAuthorsRequestToken = token
        let authors = await gitService.recentAuthors(at: repositoryURL)
        guard knownAuthorsRequestToken == token else { return }
        knownAuthors = authors
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
        selectedCommitID = nil
        selectedCommitDetail = nil
        isLoadingCommitDetail = false
        pendingDiscard = nil
        clearGraphState()
        RecentRepositoriesStore.addOrPromote(url)
        recentRepositoryURLs = RecentRepositoriesStore.load()
        lastFetchDate = nil
        lastFetchError = nil
        startAutoFetch()
        Task { await refreshStatus() }
    }

    func openMostRecentRepositoryIfNeeded() {
        guard repositoryURL == nil, let mostRecent = recentRepositoryURLs.first else { return }
        open(mostRecent)
    }
    
    func closeRepository() {
        autoFetchTask?.cancel()
        autoFetchTask = nil
        repositoryURL = nil
        lastFetchDate = nil
        lastFetchError = nil
        readme = []
        readmeFileName = nil
        readmeKey = nil
        changes = []
        selectedChangeID = nil
        currentDiff = nil
        currentBranch = nil
        commitSummary = ""
        commitDescription = ""
        commitCoAuthors = []
        knownAuthors = []
        isAmending = false
        headCommit = nil
        errorMessage = nil
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
    
    func loadGraph() async {
        guard let repositoryURL else { return }
        let token = UUID()
        graphRequestToken = token
        isLoadingGraph = true
        defer { if graphRequestToken == token { isLoadingGraph = false } }
        do {
            let commits = try await gitService.graphLog(at: repositoryURL, limit: graphCommitLimit, allBranches: graphShowsAllBranches)
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
            unpushedCommitHashes = await gitService.unpushedCommitHashes(at: repositoryURL)
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

    func deleteRemoteBranch(_ remoteBranch: String) async {
        guard let repositoryURL else { return }
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
            let outgoing = await gitService.commitsToPush(at: repositoryURL, branch: name)
            try await gitService.pushBranch(at: repositoryURL, branch: name, setUpstream: setUpstream)
            announcePush(of: name, commits: outgoing, in: repositoryURL)
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
        // The selection always comes from the graph's rows, which may span
        // every branch.
        guard let repositoryURL, let hash = selectedCommitID,
              let commit = graphRows.first(where: { $0.commit.hash == hash })?.commit.commit else {
            selectedCommitDetail = nil
            return
        }
        let token = UUID()
        commitDetailRequestToken = token
        isLoadingCommitDetail = true
        defer { if commitDetailRequestToken == token { isLoadingCommitDetail = false } }
        do {
            // Only the file list, not the diffs. A merge can carry hundreds of
            // files and one `git show` each would stall the whole selection for
            // text nobody has asked to see yet — `CommitFilesBrowser` fetches
            // the one file it is showing.
            let files = try await gitService.commitFiles(at: repositoryURL, hash: hash)
            guard commitDetailRequestToken == token else { return }
            selectedCommitDetail = CommitDetail(commit: commit, files: files)
            errorMessage = nil
        } catch {
            guard commitDetailRequestToken == token else { return }
            selectedCommitDetail = nil
            errorMessage = error.localizedDescription
        }
    }

    /// The diff of a single file in a commit, read on demand.
    ///
    /// Returns `nil` rather than raising: a file whose diff cannot be read is
    /// worth an empty pane, not an alert covering the commit behind it.
    func commitFileDiff(hash: String, file: CommitFile) async -> FileDiff? {
        guard let repositoryURL else { return nil }
        return try? await gitService.commitFileDiff(at: repositoryURL, hash: hash, pathspec: file.pathspec)
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
    
    /// Fills `branchCreatorLabels` after the list is already on screen; only
    /// branches whose tip is not cached cost a `git log`.
    func loadBranchCreators() async {
        guard let repositoryURL else { return }
        let listed = branches
        async let tipsTask = gitService.branchTips(at: repositoryURL)
        async let baseTask = gitService.creatorBase(at: repositoryURL)
        async let identityTask = try? gitService.identity(at: repositoryURL)
        let (tips, base, identity) = await (tipsTask, baseTask, identityTask)
        guard let base else { return }
        let currentUser = identity?.name

        func key(_ ref: String) -> String? { tips[ref].map { "\($0)|\(base.hash)" } }

        let missing = listed.map(BranchCreator.ref(for:)).filter { ref in
            guard let key = key(ref) else { return false }
            return creatorCache[key] == nil
        }
        if !missing.isEmpty {
            let found = await gitService.branchCreators(at: repositoryURL, refs: missing, base: base.ref)
            for ref in missing {
                if let key = key(ref) { creatorCache[key] = found[ref] ?? "" }
            }
        }

        var labels: [String: String] = [:]
        for branch in listed {
            guard let key = key(BranchCreator.ref(for: branch)),
                  let creator = creatorCache[key], !creator.isEmpty else { continue }
            labels[branch.id] = BranchCreator.label(for: creator, currentUser: currentUser)
        }
        branchCreatorLabels = labels
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
            await loadGraph()
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
            await loadGraph()
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
            lastFetchDate = .now
            lastFetchError = nil
            await refreshStatus()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Auto-fetch

    private var isAutoFetchEnabled: Bool {
        UserDefaults.standard.object(forKey: AutoFetch.enabledKey) as? Bool ?? true
    }

    /// One loop per open repository; opening another (or closing) cancels it.
    private func startAutoFetch() {
        autoFetchTask?.cancel()
        let url = repositoryURL
        autoFetchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AutoFetch.interval)
                guard !Task.isCancelled, let self, self.repositoryURL == url else { return }
                await self.backgroundFetch(minimumAge: 0)
            }
        }
    }

    /// A fetch the user did not ask for. `GIT_TERMINAL_PROMPT=0` (set in
    /// `GitService.run`) keeps git from waiting on a password, and every
    /// failure is swallowed into `lastFetchError`.
    ///
    /// Skipped while anything that writes to the repository is running: a
    /// fetch only touches remote refs, but the refresh after it would race
    /// with a half-finished commit, merge or pull.
    func backgroundFetch(minimumAge: TimeInterval) async {
        guard isAutoFetchEnabled, let repositoryURL else { return }
        guard !isFetching, !isPulling, !isPushing, !isCommitting, !isMerging,
              !isReverting, !isFinalizingMerge, mergeState == nil else { return }
        guard AutoFetch.isDue(lastFetch: lastFetchDate, minimumAge: minimumAge) else { return }
        guard await gitService.hasRemote(at: repositoryURL) else { return }

        isFetching = true
        defer { isFetching = false }

        let before = await gitService.remoteRefsSnapshot(at: repositoryURL)
        do {
            try await gitService.fetch(at: repositoryURL)
        } catch {
            if self.repositoryURL == repositoryURL { lastFetchError = error.localizedDescription }
            return
        }
        guard self.repositoryURL == repositoryURL else { return }
        lastFetchDate = .now
        lastFetchError = nil

        // refreshStatus clears errorMessage on success; a failure the user has
        // not dismissed yet must outlive a background refresh.
        let pendingError = errorMessage
        await refreshStatus()
        unpushedCommitHashes = await gitService.unpushedCommitHashes(at: repositoryURL)
        if await gitService.remoteRefsSnapshot(at: repositoryURL) != before {
            await loadGraph()
        }
        if let pendingError { errorMessage = pendingError }
    }

    // MARK: - Revert

    /// Reverting needs a quiet tree: git refuses over local edits anyway, and
    /// mid-merge there is no clean base to revert onto.
    var isRevertBlocked: Bool {
        isReverting || isCommitting || isFinalizingMerge || mergeState != nil || hasConflicts
    }

    /// Adds a commit undoing `hash`. A revert that conflicts is not a failure:
    /// it leaves REVERT_HEAD, which `refreshStatus` surfaces in the merge banner.
    func revertCommit(_ hash: String) async {
        guard let repositoryURL, !isRevertBlocked else { return }
        isReverting = true
        defer { isReverting = false }
        do {
            try await gitService.revert(at: repositoryURL, hash: hash)
            errorMessage = nil
        } catch {
            await refreshStatus()
            if mergeState?.operation == .revert {
                errorMessage = "The revert hit conflicts. Resolve them and finish the revert, or abort it."
            } else {
                errorMessage = error.localizedDescription
            }
            await loadGraph()
            return
        }
        selectedChangeID = nil
        currentDiff = nil
        await refreshStatus()
        await loadGraph()
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
            await loadGraph()
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
            await loadGraph()

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

    // MARK: - Grouped changes

    /// The changes in the order the sidebar shows them.
    ///
    /// Git lists untracked files after everything else, so staging a new file
    /// moved its row from the bottom of the list to its alphabetical place —
    /// a jump with no meaning behind it. Sorting up front takes that away:
    /// from here on a row only ever moves between sections.
    var sortedChanges: [FileChange] {
        changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Conflicts have their own section, so they are not repeated here.
    ///
    /// A file that is staged *and* has further edits on disk (`MM`) is in both
    /// lists — each shows its own half of the diff, and the checkbox is mixed.
    var stagedChanges: [FileChange] {
        sortedChanges.filter { $0.isStaged && $0.status != .unmerged }
    }

    var unstagedChanges: [FileChange] {
        sortedChanges.filter { $0.hasWorktreeChanges && $0.status != .unmerged }
    }

    /// Stages or unstages one group, without touching the others.
    func setStaged(_ staged: Bool, for group: [FileChange]) async {
        guard let repositoryURL, !isStaging, !group.isEmpty else { return }

        isStaging = true
        defer { isStaging = false }

        do {
            let paths = group.map(\.path)
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

    // MARK: - Conflicts

    /// Files git could not merge on its own. Nothing else can be committed
    /// until these are dealt with, so they are worth calling out separately
    /// rather than leaving in the list looking like ordinary changes.
    var conflictedChanges: [FileChange] {
        let unmerged = changes.filter { $0.status == .unmerged }
        // During a merge git's own list wins: it knows about conflicts the
        // porcelain letters can be coy about, and it stays right when the
        // working tree looks clean.
        guard let unresolved = mergeState?.unresolvedPaths else { return unmerged }
        return unresolved.map { path in
            unmerged.first { $0.path == path }
                ?? FileChange(path: path, originalPath: nil,
                              indexStatus: "U", worktreeStatus: "U", status: .unmerged)
        }
    }

    var hasConflicts: Bool { !conflictedChanges.isEmpty }

    /// Whether the open merge is only waiting for its commit.
    var isMergeReadyToCommit: Bool { mergeState?.isReadyToCommit ?? false }

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

        ExternalEditors.open([repositoryURL.appending(path: change.path)], in: repositoryURL, with: editor)
    }

    /// Hands the whole conflict list to the editor at once — resolving them one
    /// context menu at a time is the slow part of a big merge.
    func openAllConflicts(in editor: ExternalEditor) {
        guard let repositoryURL else { return }

        let files = conflictedChanges.map { repositoryURL.appending(path: $0.path) }
        ExternalEditors.open(files, in: repositoryURL, with: editor)
    }

    /// Stages every conflict that no longer has markers in it. Files still
    /// holding a `<<<<<<<` are left alone rather than quietly accepted.
    func markAllResolved() async {
        guard let repositoryURL, !isStaging else { return }

        let markers = mergeState?.markerPaths ?? []
        let paths = conflictedChanges.map(\.path).filter { !markers.contains($0) }
        guard !paths.isEmpty else {
            if !markers.isEmpty { errorMessage = Self.markerMessage(markers) }
            return
        }

        isStaging = true
        defer { isStaging = false }

        do {
            try await gitService.stage(at: repositoryURL, paths: paths)
            await refreshStatus()
            await loadDiff()
            errorMessage = markers.isEmpty ? nil : Self.markerMessage(markers)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes the merge commit, ending the merge.
    ///
    /// A summary the user typed wins over the message git prepared; leaving the
    /// form empty means "use git's".
    func finalizeMerge() async {
        guard let repositoryURL, let mergeState, mergeState.isReadyToCommit, !isFinalizingMerge else { return }

        guard mergeState.markerPaths.isEmpty else {
            errorMessage = Self.markerMessage(mergeState.markerPaths)
            return
        }

        isFinalizingMerge = true
        defer { isFinalizingMerge = false }

        do {
            let summary = commitSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            try await gitService.commitMerge(
                at: repositoryURL,
                summary: summary.isEmpty ? nil : summary,
                description: commitDescription.isEmpty ? nil : commitDescription,
                operation: mergeState.operation
            )
            commitSummary = ""
            commitDescription = ""
            selectedChangeID = nil
            currentDiff = nil
            await refreshStatus()
            await loadGraph()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            await refreshStatus()
        }
    }

    /// Throws the merge away and puts the branch back where it was.
    func abortMerge() async {
        guard let repositoryURL, let operation = mergeState?.operation, !isFinalizingMerge else { return }

        isFinalizingMerge = true
        defer { isFinalizingMerge = false }

        do {
            try await gitService.abortMerge(at: repositoryURL, operation: operation)
            commitSummary = ""
            commitDescription = ""
            selectedChangeID = nil
            currentDiff = nil
            await reloadAfterBranchChange()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            await refreshStatus()
        }
    }

    /// Moves git's prepared message into the commit form so it can be edited.
    func useEditableMergeMessage() {
        guard let raw = mergeState?.preparedMessage else { return }

        let parts = MergeStateParser.splitMessage(raw)
        commitSummary = parts.summary
        commitDescription = parts.description
    }

    /// The one-line summary of git's prepared message, for the banner.
    var preparedMergeSummary: String? {
        guard let raw = mergeState?.preparedMessage else { return nil }

        let summary = MergeStateParser.splitMessage(raw).summary
        return summary.isEmpty ? nil : summary
    }

    private static func markerMessage(_ paths: [String]) -> String {
        """
        Conflict markers are still in \(paths.count == 1 ? "this file" : "these files"):
        \(paths.joined(separator: "\n"))
        """
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
            let outgoing = await gitService.commitsToPush(at: repositoryURL, branch: branch)
            try await gitService.push(at: repositoryURL, branch: branch)
            announcePush(of: branch, commits: outgoing, in: repositoryURL)
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
            let outgoing = await gitService.commitsToPush(at: repositoryURL, branch: branch)
            try await gitService.push(at: repositoryURL, branch: branch)
            announcePush(of: branch, commits: outgoing, in: repositoryURL)
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
        await loadGraph()
    }

    private func announcePush(of branch: String, commits: [Commit], in repositoryURL: URL) {
        guard !commits.isEmpty else { return }
        onPush?(PushedWork(repositoryURL: repositoryURL, branch: branch, commits: commits))
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
            await loadGraph()
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

    /// The open pull request for the branch checked out, if there is one.
    func openPullRequest() async -> PullRequestSummary? {
        guard let repositoryURL, let branch = currentBranch else { return nil }
        return await gitHubService.openPullRequest(at: repositoryURL, head: branch)
    }

    /// What the create sheet opens with, for a pull request from the branch
    /// checked out into `base` — `nil` meaning the repository's default branch.
    func pullRequestDraft(base: String?) async -> PullRequestDraft {
        guard let repositoryURL, let branch = currentBranch else {
            return PullRequestDraft(title: "", body: "", commitCount: 0)
        }
        let resolvedBase: String
        if let base {
            resolvedBase = base
        } else {
            resolvedBase = await gitService.defaultBranch(at: repositoryURL) ?? ""
        }
        let commits = (try? await gitService.commitsAhead(
            at: repositoryURL, base: resolvedBase, head: branch
        )) ?? []

        // Only worth a second call for the one case that reads it: a lone
        // commit, whose body becomes the pull request's.
        var message: String?
        if commits.count == 1 {
            message = try? await gitService.commitMessage(at: repositoryURL, hash: commits[0].hash)
        }
        return PullRequestDraftBuilder.draft(
            branch: branch, commits: commits, singleCommitMessage: message
        )
    }

    func createPullRequest(title: String, description: String, base: String?) async {
        guard let repositoryURL else { return }
        isCreatingPullRequest = true
        defer { isCreatingPullRequest = false }
        do {
            if let branch = currentBranch {
                let outgoing = await gitService.commitsToPush(at: repositoryURL, branch: branch)
                try await gitService.push(at: repositoryURL, branch: branch)
                announcePush(of: branch, commits: outgoing, in: repositoryURL)
            }

            if await gitHubService.isAvailable() {
                let output = try await gitHubService.createPullRequest(
                    at: repositoryURL, title: title, body: description, base: base
                )
                if let url = URL(string: output) {
                    NSWorkspace.shared.open(url)
                }
                // Only here: the browser fallback below opens a form, not a pull request.
                if let branch = currentBranch { onPullRequestCreated?(branch) }
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

    // MARK: - Partial staging

    enum PartialAction {
        case stage, unstage, discard
    }

    struct PendingLineDiscard {
        let patch: String
        let lineCount: Int
        let fileName: String
    }

    /// A file whose staged or unstaged half vanished (everything staged, or
    /// everything unstaged) follows its changes to the other section instead of
    /// being left looking at an empty diff.
    private func reconcileDiffSide() {
        guard let change = selectedChange, change.status != .unmerged else { return }
        if selectedDiffSide == .unstaged, !change.hasWorktreeChanges, change.isStaged {
            selectedDiffSide = .staged
        } else if selectedDiffSide == .staged, !change.isStaged, change.hasWorktreeChanges {
            selectedDiffSide = .unstaged
        }
    }

    /// Row tags for the sidebar list: a partly staged file has two rows with
    /// the same file id, so the id alone cannot say which one is selected.
    var sidebarSelection: String? {
        get { selectedChangeID.map { Self.sidebarTag($0, side: selectedDiffSide) } }
        set {
            guard let newValue else {
                selectedChangeID = nil
                return
            }
            if newValue.hasPrefix("staged:") {
                selectedDiffSide = .staged
                selectedChangeID = String(newValue.dropFirst("staged:".count))
            } else {
                selectedDiffSide = .unstaged
                selectedChangeID = String(newValue.dropFirst("unstaged:".count))
            }
        }
    }

    static func sidebarTag(_ id: FileChange.ID, side: DiffSide) -> String {
        (side == .staged ? "staged:" : "unstaged:") + id
    }

    /// What the diff pane may do with the diff on screen, or nil for none.
    func diffInteraction(for diff: FileDiff) -> DiffInteraction? {
        guard let change = selectedChange,
              let mode = diff.partialMode(for: change, side: selectedDiffSide),
              !isStagingBlockedByWhitespace
        else { return nil }

        let wholeFile = mode == .wholeFile
        return DiffInteraction(
            side: selectedDiffSide,
            mode: mode,
            selection: diffSelection,
            canDiscard: change.status != .untracked && !wholeFile,
            identity: "\(change.id)|\(selectedDiffSide)",
            onStageHunk: { [weak self] header in
                guard let self else { return }
                Task { await self.perform(.stage, lines: self.hunkLines(header)) }
            },
            onUnstageHunk: { [weak self] header in
                guard let self else { return }
                Task { await self.perform(.unstage, lines: self.hunkLines(header)) }
            },
            onDiscardHunk: { [weak self] header in
                guard let self else { return }
                self.requestLineDiscard(self.hunkLines(header))
            }
        )
    }

    private func hunkLines(_ headerIndex: Int) -> Set<Int> {
        guard let diff = currentDiff, diff.lines.indices.contains(headerIndex),
              let hunk = diff.lines[headerIndex].hunkIndex
        else { return [] }
        return diff.changedLineIndices(inHunk: hunk)
    }

    func stageSelectedLines() async { await perform(.stage, lines: diffSelection.lines) }
    func unstageSelectedLines() async { await perform(.unstage, lines: diffSelection.lines) }
    func requestDiscardSelectedLines() { requestLineDiscard(diffSelection.lines) }

    private func requestLineDiscard(_ lines: Set<Int>) {
        guard let diff = currentDiff, let change = selectedChange, !lines.isEmpty, !isStagingBlockedByWhitespace,
              let patch = PatchBuilder.build(diff: diff, selected: lines, direction: .reverse)
        else { return }
        pendingLineDiscard = PendingLineDiscard(patch: patch, lineCount: lines.count, fileName: change.fileName)
    }

    func cancelLineDiscard() {
        pendingLineDiscard = nil
    }

    func confirmLineDiscard() async {
        guard let pending = pendingLineDiscard else { return }
        pendingLineDiscard = nil
        await applyChange(wholeFileStage: nil) { service, url in
            try await service.applyPatch(at: url, patch: pending.patch, cached: false, reverse: true)
        }
    }

    /// Stages, unstages or discards `lines` of the diff on screen.
    private func perform(_ action: PartialAction, lines: Set<Int>) async {
        guard let diff = currentDiff, let change = selectedChange, !lines.isEmpty, !isStagingBlockedByWhitespace,
              let mode = diff.partialMode(for: change, side: selectedDiffSide)
        else { return }

        if mode == .wholeFile {
            // One hunk *is* the file, so the hunk's button is the file's checkbox.
            switch action {
            case .stage: await applyChange(wholeFileStage: (change.path, true)) { _, _ in }
            case .unstage: await applyChange(wholeFileStage: (change.path, false)) { _, _ in }
            case .discard: break
            }
            return
        }

        let direction: PatchBuilder.Direction = action == .stage ? .forward : .reverse
        guard let patch = PatchBuilder.build(diff: diff, selected: lines, direction: direction) else { return }

        await applyChange(wholeFileStage: nil) { service, url in
            try await service.applyPatch(at: url, patch: patch, cached: action != .discard, reverse: action != .stage)
        }
    }

    /// Runs one git change, then brings status and the diff up to date without
    /// letting go of the open file: the diff is swapped in place (the view keeps
    /// its scroll position) and the selection is dropped.
    private func applyChange(wholeFileStage: (path: String, stage: Bool)?,
                     _ work: @escaping (GitService, URL) async throws -> Void) async {
        guard let repositoryURL, !isStaging else { return }
        isStaging = true
        defer { isStaging = false }

        var failure: String?
        do {
            if let wholeFileStage {
                if wholeFileStage.stage {
                    try await gitService.stage(at: repositoryURL, path: wholeFileStage.path)
                } else {
                    try await gitService.unstage(at: repositoryURL, path: wholeFileStage.path)
                }
            } else {
                try await work(gitService, repositoryURL)
            }
            diffSelection.clear()
        } catch {
            failure = error.localizedDescription
        }

        await refreshStatus()
        if selectedChange == nil {
            // Nothing left of this file to show.
            selectedChangeID = nil
            currentDiff = nil
            loadedDiffKey = nil
        } else {
            await loadDiff()
        }
        if let failure { errorMessage = failure }
    }
}

