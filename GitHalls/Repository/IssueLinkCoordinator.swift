//
//  IssueLinkCoordinator.swift
//  GitHalls
//

import Foundation
import Observation

/// Where git and Jira meet. A branch belongs to the issues whose keys are in
/// its name — the same rule Jira's development panel follows, so a branch made
/// anywhere links the same way — and to any linked to it by hand, which is how
/// a branch with no key gets one, or how two cards share one branch.
///
/// What the link does:
/// - the checked-out branch's issues are shown, and the next commit names them;
/// - a push posts the commits it sent as a comment on each of its issues;
/// - opening a pull request offers to move them to review, and a merged one
///   offers to move them to done;
/// - switching to a branch offers to start the Clockify timer for its issue.
///
/// Offers wait for a click. A comment is the one thing done unasked, and the
/// switch for it lives in Settings › Jira.
@Observable
@MainActor
final class IssueLinkCoordinator {
    let jira: JiraViewModel
    let repository: RepositoryViewModel
    let clockify: ClockifyViewModel

    private let git = GitService()
    private let gitHub = GitHubService()

    /// The issues the checked-out branch belongs to, once Jira has confirmed them.
    private(set) var currentIssues: [JiraIssue] = []
    /// Every pull request from the checked-out branch, newest first.
    private(set) var currentPullRequests: [PullRequestStatus] = []

    var currentKeys: Set<String> { Set(currentIssues.map(\.key)) }

    /// Waiting for a click, oldest first; the banner shows the first.
    private(set) var offers: [IssueLinkOffer] = []
    var offer: IssueLinkOffer? { offers.first }

    /// Issue keys with a branch in the open repository, for the board's badges.
    private(set) var keysWithBranches: Set<String> = []

    /// Offers already answered this session, so a refresh does not repeat them.
    private var answered: Set<String> = []

    /// The branch seen last, to tell a switch from the first look at launch.
    private var lastBranch: String?

    init(jira: JiraViewModel, repository: RepositoryViewModel, clockify: ClockifyViewModel) {
        self.jira = jira
        self.repository = repository
        self.clockify = clockify

        repository.onPush = { [weak self] work in
            Task { await self?.pushed(work) }
        }
        repository.onPullRequestCreated = { [weak self] branch in
            Task { await self?.pullRequestCreated(on: branch) }
        }
    }

    // MARK: - Which issues a branch has

    func keys(forBranch branch: String, in repositoryURL: URL?) -> [String] {
        let manual = repositoryURL.map { BranchLinkStore.keys(repository: $0, branch: branch) } ?? []
        return IssueLinkRules.keys(forBranch: branch, manual: manual)
    }

    func isManual(_ key: String, branch: String, in repositoryURL: URL) -> Bool {
        BranchLinkStore.keys(repository: repositoryURL, branch: branch).contains(key.uppercased())
    }

    /// Links an issue to a branch by hand, once Jira says the key is real.
    /// Answers why not, or nil when it worked.
    func link(_ text: String, toBranch branch: String, in repositoryURL: URL) async -> String? {
        guard let key = JiraIssueKey.find(in: text) else { return "No issue key in “\(text)”." }
        guard (try? await jira.fetchIssue(key: key)) != nil else { return "Jira has no issue \(key) you can see." }

        BranchLinkStore.link(key, repository: repositoryURL, branch: branch)
        await linksChanged(branch: branch, in: repositoryURL)
        return nil
    }

    func unlink(_ key: String, fromBranch branch: String, in repositoryURL: URL) async {
        BranchLinkStore.unlink(key, repository: repositoryURL, branch: branch)
        await linksChanged(branch: branch, in: repositoryURL)
    }

    private func linksChanged(branch: String, in repositoryURL: URL) async {
        branchesChanged()
        if repositoryURL == repository.repositoryURL, branch == repository.currentBranch {
            await branchChanged(force: true)
        }
    }

    // MARK: - The checked-out branch

    /// Called whenever the branch or the repository changes; `force` re-reads
    /// the issues even when the branch is the same, after a link changed.
    func branchChanged(force: Bool = false) async {
        let branch = repository.currentBranch
        // Launch goes from no branch to the current one; that is not a switch.
        let isSwitch = lastBranch != nil && branch != lastBranch
        lastBranch = branch

        guard let branch, JiraCredentialsStore.isConfigured else {
            clearCurrent()
            return
        }
        let keys = keys(forBranch: branch, in: repository.repositoryURL)
        guard !keys.isEmpty else {
            clearCurrent()
            return
        }

        if force || currentIssues.map(\.key) != keys {
            var issues: [JiraIssue] = []
            // A key Jira does not know ("release-2") links nothing.
            for key in keys {
                if let issue = try? await jira.fetchIssue(key: key) { issues.append(issue) }
            }
            guard repository.currentBranch == branch else { return }
            currentIssues = issues
        }

        repository.linkedIssueKeys = IssueLinkPreferences.addKeyToCommits ? currentIssues.map(\.key) : []
        await refreshPullRequest()
        if isSwitch, !currentIssues.isEmpty { await offerTimer(for: currentIssues) }
    }

    private func clearCurrent() {
        currentIssues = []
        currentPullRequests = []
        repository.linkedIssueKeys = []
    }

    /// Asks GitHub where the branch's pull requests stand — one per base — and
    /// offers the move the table in Settings gives for the furthest stage. Run
    /// on a branch change and whenever the app comes back to the front, which
    /// is when an approval or a merge done in the browser shows up.
    func refreshPullRequest(justOpened: Bool = false) async {
        guard !currentIssues.isEmpty, let url = repository.repositoryURL, let branch = repository.currentBranch else { return }
        currentPullRequests = await gitHub.pullRequests(at: url, head: branch)
        guard !currentPullRequests.isEmpty else { return }

        let defaultBranch = await git.defaultBranch(at: url)
        for issue in currentIssues {
            await offerMove(for: issue, pullRequests: currentPullRequests,
                            defaultBranch: defaultBranch, justOpened: justOpened)
        }
    }

    func branchesChanged() {
        var keys = Set(repository.branches.flatMap { JiraIssueKey.all(in: $0.name) })
        if let url = repository.repositoryURL { keys.formUnion(BranchLinkStore.linkedKeys(repository: url)) }
        keysWithBranches = keys
    }

    // MARK: - Push → comment

    func pushed(_ work: PushedWork) async {
        guard IssueLinkPreferences.postCommits, JiraCredentialsStore.isConfigured else { return }

        let remote = try? await git.remoteURL(at: work.repositoryURL)
        let branchKeys = keys(forBranch: work.branch, in: work.repositoryURL)

        for (key, commits) in IssueLinkRules.group(work.commits, branchKeys: branchKeys) {
            let posted = PostedCommitsStore.posted(on: key)
            let fresh = commits.filter { !posted.contains($0.hash) }
            guard !fresh.isEmpty else { continue }

            guard (try? await jira.fetchIssue(key: key)) != nil else { continue }

            let text = IssueLinkRules.comment(
                branch: work.branch,
                repository: work.repositoryURL.lastPathComponent,
                commits: fresh
            ) { IssueLinkRules.commitURL(remote: remote, hash: $0.hash) }

            if await jira.addComment(to: key, text: text) {
                PostedCommitsStore.record(fresh.map(\.hash), on: key)
            }
        }
    }

    // MARK: - Pull requests → status

    func pullRequestCreated(on branch: String) async {
        guard branch == repository.currentBranch else { return }
        await refreshPullRequest(justOpened: true)
    }

    private func offerMove(for issue: JiraIssue, pullRequests: [PullRequestStatus],
                           defaultBranch: String?, justOpened: Bool) async {
        guard IssueLinkPreferences.offerMoves,
              let transitions = try? await jira.transitions(for: issue),
              let move = PullRequestFlow.move(
                  pullRequests: pullRequests,
                  rules: PullRequestFlowStore.rules,
                  defaultBranch: defaultBranch,
                  transitions: transitions,
                  currentStatus: issue.status,
                  currentCategory: issue.statusCategory,
                  includeAutomaticOpened: justOpened
              )
        else { return }
        present(.move(issue, move.transition, move.trigger))
    }

    // MARK: - Branch → Clockify

    private func offerTimer(for issues: [JiraIssue]) async {
        guard IssueLinkPreferences.offerTimer, clockify.isConfigured else { return }
        await clockify.load()
        await clockify.refreshRunning()
        let running = clockify.running?.description ?? ""
        guard !issues.contains(where: { running.contains("[\($0.key)]") }) else { return }
        present(.startTimer(issues))
    }

    // MARK: - Acting on an offer

    private func present(_ offer: IssueLinkOffer) {
        guard !answered.contains(offer.id), !offers.contains(offer) else { return }
        offers.append(offer)
    }

    func dismissOffer() {
        guard let offer else { return }
        answered.insert(offer.id)
        offers.removeFirst()
    }

    /// `issue` picks which one to time when the offer names several.
    func accept(_ offer: IssueLinkOffer, issue chosen: JiraIssue? = nil) async {
        answered.insert(offer.id)
        offers.removeAll { $0 == offer }

        switch offer {
        case .startTimer(let issues):
            guard let issue = chosen ?? issues.first else { return }
            let entry = await clockify.draft(key: issue.key, summary: issue.summary)
            _ = await clockify.startTimer(entry)
        case .move(let issue, let transition, _):
            if await jira.move(issue, to: transition),
               let index = currentIssues.firstIndex(where: { $0.key == issue.key }),
               let fresh = try? await jira.fetchIssue(key: issue.key) {
                currentIssues[index] = fresh
            }
        }
    }

    // MARK: - Branches for an issue

    /// Every branch of `key` — named for it, or linked to it by hand — in the
    /// open repository and the recent ones, with its pull request. Local and
    /// remote copies of a branch are one row.
    func branches(for key: String) async -> [LinkedBranch] {
        var repositories: [URL] = []
        for url in [repository.repositoryURL].compactMap({ $0 }) + repository.recentRepositoryURLs
        where !repositories.contains(url) && FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
            repositories.append(url)
        }

        var found: [LinkedBranch] = []
        for url in repositories {
            guard let all = try? await git.branches(at: url) else { continue }
            let isOpen = url == repository.repositoryURL
            let manual = Set(BranchLinkStore.branches(linkedTo: key, repository: url))

            var byName: [String: (local: Bool, remote: Bool, current: Bool)] = [:]
            for branch in all {
                let name = branch.isRemote ? Branch.remoteShortName(from: branch.name) : branch.name
                guard name != "HEAD", !name.hasPrefix("HEAD "),
                      JiraIssueKey.mentions(key, in: name) || manual.contains(name)
                else { continue }
                var entry = byName[name] ?? (false, false, false)
                if branch.isRemote { entry.remote = true } else { entry.local = true }
                if branch.isCurrent, isOpen { entry.current = true }
                byName[name] = entry
            }

            for (name, entry) in byName.sorted(by: { $0.key < $1.key }) {
                found.append(LinkedBranch(
                    repositoryURL: url, name: name,
                    isLocal: entry.local, hasRemote: entry.remote, isCurrent: entry.current,
                    isManual: manual.contains(name) && !JiraIssueKey.mentions(key, in: name),
                    pullRequests: entry.remote ? await gitHub.pullRequests(at: url, head: name) : []
                ))
            }
        }
        return found
    }

    /// Checks the branch out, opening its repository first when it is another one.
    func checkout(_ branch: LinkedBranch) async {
        if repository.repositoryURL != branch.repositoryURL {
            repository.open(branch.repositoryURL)
        }
        await repository.switchBranch(to: branch.name)
    }
}
