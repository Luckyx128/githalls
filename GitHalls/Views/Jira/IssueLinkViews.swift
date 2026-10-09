//
//  IssueLinkViews.swift
//  GitHalls
//

import SwiftUI

/// The checked-out branch's issues, beside the branch in the toolbar: key,
/// status and, once there is one, the pull request. A click opens the first
/// issue; the menu opens the others, links another one, or unlinks one linked
/// by hand. A branch with no issue offers to link one.
struct CurrentIssueButton: View {
    @Bindable var link: IssueLinkCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var isLinking = false

    private var branch: String? { link.repository.currentBranch }
    private var repositoryURL: URL? { link.repository.repositoryURL }

    var body: some View {
        if let branch, let repositoryURL, JiraCredentialsStore.isConfigured {
            Group {
                if let first = link.currentIssues.first {
                    Menu {
                        menuItems(branch: branch, repositoryURL: repositoryURL)
                    } label: {
                        label(for: first)
                    } primaryAction: {
                        openWindow(id: "issue", value: first)
                    }
                    .menuIndicator(.visible)
                    .fixedSize()
                    .help(link.currentIssues.map { "\($0.key) — \($0.summary)" }.joined(separator: "\n")
                          + "\nClick to open; the arrow lists every issue on this branch.")
                } else {
                    Button {
                        isLinking = true
                    } label: {
                        Label("Link Issue", systemImage: "link")
                    }
                    .help("Link a Jira issue to \(branch)")
                }
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .padding(.horizontal, 10)
            .popover(isPresented: $isLinking) {
                LinkIssuePopover(branch: branch, repositoryURL: repositoryURL, link: link) { isLinking = false }
            }
        }
    }

    private func label(for first: JiraIssue) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(KanbanColumnView.color(for: first.statusCategory))
                .frame(width: 7, height: 7)
            Text(first.key).fontDesign(.monospaced).bold()
            Text(first.status).foregroundStyle(.secondary)
            if link.currentIssues.count > 1 {
                Text("+\(link.currentIssues.count - 1)").foregroundStyle(.secondary)
            }
            ForEach(PullRequestFlow.latestPerBase(link.currentPullRequests.filter { $0.state != .closed }).prefix(3),
                    id: \.pullRequest.number) { entry in
                PullRequestBadge(pullRequest: entry.pullRequest)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func menuItems(branch: String, repositoryURL: URL) -> some View {
        Section("Issues on this branch") {
            ForEach(link.currentIssues, id: \.key) { issue in
                Button("\(issue.key) — \(issue.summary)") { openWindow(id: "issue", value: issue) }
            }
        }
        Divider()
        Button("Link Another Issue…") { isLinking = true }
        let manual = link.currentIssues.filter { link.isManual($0.key, branch: branch, in: repositoryURL) }
        if !manual.isEmpty {
            Menu("Unlink") {
                ForEach(manual, id: \.key) { issue in
                    Button(issue.key) {
                        Task { await link.unlink(issue.key, fromBranch: branch, in: repositoryURL) }
                    }
                }
            }
        }
    }
}

/// Type or paste a key — or the issue's URL — to link it to a branch.
struct LinkIssuePopover: View {
    let branch: String
    let repositoryURL: URL
    @Bindable var link: IssueLinkCoordinator
    let onDone: () -> Void

    @State private var text = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Link an issue to \(branch)").font(.headline).lineLimit(1)
            Text("Its pushes, pull request and timer will follow this issue too.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                TextField("SWEB-1234 or the issue's link", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onSubmit(submit)
                Button("Link", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || JiraIssueKey.find(in: text) == nil)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
        }
        .padding(14)
    }

    private func submit() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            error = await link.link(text, toBranch: branch, in: repositoryURL)
            isWorking = false
            if error == nil { onDone() }
        }
    }
}

struct PullRequestBadge: View {
    let pullRequest: PullRequestStatus

    var body: some View {
        Label {
            Text(pullRequest.baseRefName.isEmpty ? "#\(pullRequest.number)" : pullRequest.baseRefName)
        } icon: {
            Image(systemName: symbol)
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(color)
        .help(help)
    }

    private var symbol: String {
        switch pullRequest.state {
        case .open: pullRequest.isApproved ? "checkmark.seal" : "arrow.triangle.pull"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle"
        }
    }

    private var color: Color {
        switch pullRequest.state {
        case .open: .green
        case .merged: .purple
        case .closed: .secondary
        }
    }

    private var help: String {
        let state = switch pullRequest.state {
        case .open: pullRequest.isApproved ? "approved, waiting to merge" : "open"
        case .merged: "merged"
        case .closed: "closed"
        }
        let base = pullRequest.baseRefName.isEmpty ? "" : " into \(pullRequest.baseRefName)"
        return "Pull request #\(pullRequest.number)\(base) is \(state): \(pullRequest.title)"
    }
}

/// One offer at a time, across the top of the window: move the issue now that
/// its pull request moved, or start the timer for the branch just checked out.
struct IssueLinkBanner: View {
    @Bindable var link: IssueLinkCoordinator
    @State private var isWorking = false

    var body: some View {
        if let offer = link.offer {
            HStack(spacing: 10) {
                Image(systemName: symbol(for: offer))
                    .foregroundStyle(.tint)
                Text(message(for: offer))
                    .lineLimit(2)
                Spacer()
                Button("Not Now") { link.dismissOffer() }
                if case .startTimer(let issues) = offer, issues.count > 1 {
                    // One timer at a time: the user says which issue it is for.
                    Menu("Start Timer for…") {
                        ForEach(issues, id: \.key) { issue in
                            Button("\(issue.key) — \(issue.summary)") { accept(offer, issue: issue) }
                        }
                    }
                    .fixedSize()
                    .disabled(isWorking)
                } else {
                    Button(action: { accept(offer) }) {
                        if isWorking { ProgressView().controlSize(.small) } else { Text(actionTitle(for: offer)) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func accept(_ offer: IssueLinkOffer, issue: JiraIssue? = nil) {
        isWorking = true
        Task {
            await link.accept(offer, issue: issue)
            isWorking = false
        }
    }

    private func symbol(for offer: IssueLinkOffer) -> String {
        switch offer {
        case .startTimer: "timer"
        case .move(_, _, let trigger): trigger.event == .merged ? "arrow.triangle.merge" : "arrow.triangle.pull"
        }
    }

    private func message(for offer: IssueLinkOffer) -> String {
        switch offer {
        case .startTimer(let issues):
            issues.count == 1
                ? "You switched to \(issues[0].key). Start its Clockify timer?"
                : "This branch carries \(issues.map(\.key).formatted()). Start a Clockify timer?"
        case .move(let issue, let transition, let trigger):
            "Pull request #\(trigger.number) into \(trigger.base) \(trigger.event.past). "
                + "Move \(issue.key) from \(issue.status) to \(transition.toStatus)?"
        }
    }

    private func actionTitle(for offer: IssueLinkOffer) -> String {
        switch offer {
        case .startTimer: "Start Timer"
        case .move(_, let transition, _): "Move to \(transition.toStatus)"
        }
    }
}

/// The branches of this issue in every repository GitHalls knows — named for
/// it or linked by hand — each in a card of its own: the branch and where it
/// lives on top, its pull requests below, one line per branch they go into.
struct IssueBranchesView: View {
    let issueKey: String
    @Bindable var link: IssueLinkCoordinator

    @State private var branches: [LinkedBranch] = []
    @State private var isLoading = false
    @State private var switching: LinkedBranch.ID?
    @State private var linkError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IssueSectionHeader("Branches & Pull Requests", systemImage: "arrow.triangle.branch") {
                if isLoading { ProgressView().controlSize(.small) }
                linkBranchMenu
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .pointerStyle(.link)
                    .help("Look again")
                    .disabled(isLoading)
            }

            if let linkError { Text(linkError).font(.callout).foregroundStyle(.red) }

            if branches.isEmpty, !isLoading {
                Text("No branch of \(issueKey) in your recent repositories yet. Create one below, or link an existing one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(branches) { branch in
                branchCard(branch)
            }
        }
        .task(id: issueKey) { await load() }
    }

    // MARK: - One branch

    private func branchCard(_ branch: LinkedBranch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
                Text(branch.name)
                    .fontDesign(.monospaced)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(branch.name)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                checkoutControl(branch)
            }

            HStack(spacing: 6) {
                Label(branch.repositoryName, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(branch.repositoryURL.path)
                Text("·")
                Text(whereItLives(branch))
                if branch.isManual {
                    Text("·")
                    HStack(spacing: 3) {
                        Text("linked by hand")
                        Button {
                            Task {
                                await link.unlink(issueKey, fromBranch: branch.name, in: branch.repositoryURL)
                                await load()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .pointerStyle(.link)
                        .help("Unlink \(issueKey) from this branch")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            let latest = PullRequestFlow.latestPerBase(branch.pullRequests)
            if !latest.isEmpty {
                Divider()
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                    ForEach(latest, id: \.pullRequest.number) { entry in
                        pullRequestRow(entry.pullRequest, earlier: entry.earlier)
                    }
                }
            } else if branch.hasRemote {
                Text("No pull request yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(branch.isCurrent ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08))
        }
    }

    private func pullRequestRow(_ pullRequest: PullRequestStatus, earlier: Int) -> some View {
        GridRow {
            Text(pullRequest.baseRefName.isEmpty ? "—" : pullRequest.baseRefName)
                .font(.caption.monospaced())
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())

            PullRequestStateLabel(pullRequest: pullRequest)
                .fixedSize()

            Link("#\(pullRequest.number)", destination: URL(string: pullRequest.url) ?? URL(string: "https://github.com")!)
                .pointerStyle(.link)
                .help("Open pull request #\(pullRequest.number) on GitHub")

            HStack(spacing: 6) {
                Text(pullRequest.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(pullRequest.title)
                if earlier > 0 {
                    Text("+\(earlier) earlier")
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .help("\(earlier) older pull request\(earlier == 1 ? "" : "s") into \(pullRequest.baseRefName) from this branch")
                }
            }
            .gridColumnAlignment(.leading)
        }
        .font(.callout)
    }

    @ViewBuilder
    private func checkoutControl(_ branch: LinkedBranch) -> some View {
        if branch.isCurrent {
            Label("Checked out", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
                .fixedSize()
        } else if switching == branch.id {
            ProgressView().controlSize(.small)
        } else {
            Button("Check Out") {
                switching = branch.id
                Task {
                    await link.checkout(branch)
                    switching = nil
                    await load()
                }
            }
            .controlSize(.small)
            .fixedSize()
            .disabled(switching != nil)
            .help(branch.repositoryURL == link.repository.repositoryURL
                  ? "Switch to this branch"
                  : "Open \(branch.repositoryName) and switch to this branch")
        }
    }

    private func whereItLives(_ branch: LinkedBranch) -> String {
        switch (branch.isLocal, branch.hasRemote) {
        case (true, true): "local and on the remote"
        case (true, false): "local only, not pushed"
        case (false, true): "on the remote only"
        case (false, false): "—"
        }
    }

    // MARK: - Linking

    /// Local branches of the open repository not already listed: the ones
    /// whose name has no key for this issue, which only a hand link can join.
    private var linkBranchMenu: some View {
        let listed = Set(branches.filter { $0.repositoryURL == link.repository.repositoryURL }.map(\.name))
        let candidates = link.repository.branches.filter { !$0.isRemote && !listed.contains($0.name) }

        return Menu {
            if let repositoryURL = link.repository.repositoryURL {
                Section("Branches of \(repositoryURL.lastPathComponent)") {
                    ForEach(candidates) { branch in
                        Button(branch.name) {
                            Task {
                                linkError = await link.link(issueKey, toBranch: branch.name, in: repositoryURL)
                                await load()
                            }
                        }
                    }
                }
            }
        } label: {
            Label("Link a Branch", systemImage: "link")
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .disabled(candidates.isEmpty || link.repository.repositoryURL == nil)
        .help(link.repository.repositoryURL.map { "Link \(issueKey) to a branch of \($0.lastPathComponent)" }
              ?? "Open a repository to link one of its branches")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        branches = await link.branches(for: issueKey)
    }
}

/// "Merged", "Approved", "Open", "Closed" with its symbol and colour.
struct PullRequestStateLabel: View {
    let pullRequest: PullRequestStatus

    var body: some View {
        Label(title, systemImage: symbol)
            .foregroundStyle(color)
    }

    private var title: String {
        switch pullRequest.state {
        case .open: pullRequest.isApproved ? "Approved" : "Open"
        case .merged: "Merged"
        case .closed: "Closed"
        }
    }

    private var symbol: String {
        switch pullRequest.state {
        case .open: pullRequest.isApproved ? "checkmark.seal.fill" : "arrow.triangle.pull"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle"
        }
    }

    private var color: Color {
        switch pullRequest.state {
        case .open: .green
        case .merged: .purple
        case .closed: .secondary
        }
    }
}
