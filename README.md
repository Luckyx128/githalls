# GitHalls

A native macOS git client, built from scratch with SwiftUI. List changed
files, review colored diffs with syntax highlighting, stage and commit,
browse history, manage branches, sync with a remote, merge with a clear
visual of which branch actually changes, and jump straight from a Jira
card to a new branch — all without leaving a native Mac window.

No Electron, no bundled runtime, no third-party dependencies. Every git
operation shells out to the `git` binary already installed on your Mac,
the same way the Terminal would.

Built with native SwiftUI + the Observation framework. macOS 26+.

## Features

- **Changes** — lists everything `git status` sees (modified, added,
  deleted, renamed, copied, untracked, unmerged), with per-file and
  select-all staging, a commit form (summary + description), and
  discard-changes with a confirmation dialog before anything destructive
  happens.
- **Diff view** — colored addition/deletion/context lines, a friendly
  hunk-header label instead of raw `@@ ... @@` syntax, a `+`/`-` gutter
  column, and lightweight syntax highlighting (a hand-rolled scanner —
  keywords, strings, numbers, comments — no external highlighting
  library). Handles binary files, merge-commit diffs, and files without a
  trailing newline without corrupting the view.
- **History** — full commit log with author, relative date, and short
  hash. Selecting a commit shows every file it touched, each in its own
  collapsible diff section.
- **Branches** — list, switch, and create branches from a popover, with
  the current branch always visible in the toolbar.
- **Sync** — a single toolbar button that adapts to what's needed:
  *Push (N)* when you have unpushed commits, *Pull (N)* when the remote is
  ahead, *Publish Branch* for a branch that's never been pushed, or
  *Up to date*. Fetches automatically whenever the app regains focus.
- **Merge** — a dedicated sheet that names both branches explicitly and
  states plainly which one is about to change, instead of assuming you
  remember that a merge always updates the branch you're currently on.
- **Recent repositories** — the last opened repository reopens
  automatically on launch; a short list of recents lets you jump between
  repos without the Finder picker every time.
- **Jira integration** — connect a Jira Cloud account (site, email, API
  token, stored in the Keychain), browse issues assigned to you grouped
  by status in a Kanban-style sidebar, and create a branch from a
  selected card with one click — the branch name is auto-suggested from
  the issue key and summary, and editable before you commit to it.

## Build & run

```bash
open GitHalls.xcodeproj   # then Cmd+R in Xcode
```

or from the command line:

```bash
xcodebuild -project GitHalls.xcodeproj -scheme GitHalls -configuration Release build
```

Run the test suite (parsers and the Jira branch-name helper are covered
with `Swift Testing`):

```bash
xcodebuild -project GitHalls.xcodeproj -scheme GitHalls -configuration Debug test -destination 'platform=macOS'
```

The app is unsandboxed (`ENABLE_APP_SANDBOX = NO`) — this is required to
spawn `git` as a subprocess, and it's the same tradeoff GitHub Desktop,
Fork, and Tower make. It means GitHalls isn't distributed through the Mac
App Store, only as a direct download.

## Architecture

```
GitHalls/
├─ GitHallsApp.swift        Two Scenes: the main window and a Settings window (Jira connection)
├─ ContentView.swift        NavigationSplitView: sidebar mode picker + detail pane per mode
├─ GIt/                     Everything that talks to git — no SwiftUI in this folder
│  ├─ GitService.swift      actor wrapping Process; every git subcommand is a typed method
│  ├─ StatusParser.swift    `git status --porcelain=v1` → [FileChange]
│  ├─ DiffParser.swift      unified diff text → [DiffLine], with graceful handling of
│  │                        binary/merge/no-trailing-newline edge cases
│  ├─ CommitLogParser.swift `git log` (control-character delimited) → [Commit]
│  ├─ BranchParser.swift    `git branch --list` → [Branch]
│  └─ FileChange.swift, FileDiff.swift, Commit.swift, GitError.swift, Branch.swift
├─ Jira/                    Jira Cloud client — myself()/search(jql:), Keychain-backed credentials
├─ Repository/
│  ├─ RepositoryViewModel.swift   @Observable @MainActor — owns repo state, orchestrates GitService
│  ├─ JiraViewModel.swift         separate @Observable — Jira state, doesn't know about git
│  └─ RecentRepositoriesStore.swift
└─ Views/                   One SwiftUI view per concern: ChangesSidebarView, DiffView,
                             HistorySidebarView, CommitDetailView, BranchSwitcherView,
                             MergeSheetView, SyncButton, KanbanSidebarView, IssueDetailView,
                             JiraSettingsView, SyntaxHighlighter
```

Key pieces:

- `GitService` is a Swift `actor` that wraps `Process`. Every method drains
  stdout, stderr, and the exit status concurrently via `async let` — reading
  them sequentially would deadlock on any output larger than the pipe's
  OS buffer (~64KB), a classic bug in hand-rolled `Process` wrappers.
- Every screen follows the same rhythm: a parser turns raw git text into a
  typed model, a view model orchestrates `GitService` calls and holds
  UI state, and a view renders it. Async loads triggered by a changing
  selection (a different file, commit, or repository) are guarded with a
  "is this still the most recent request?" token, so a slow response for a
  selection you've since moved away from can't silently overwrite what's
  on screen.
- `RepositoryViewModel` and `JiraViewModel` are deliberately separate —
  Jira is not git, and `RepositoryViewModel` already owns enough (status,
  diff, staging, commits, branches, sync, merge). The only place the two
  meet is `IssueDetailView`, which holds both and calls
  `repositoryViewModel.createBranch(named:)` directly when you click
  "Create Branch."

## Known limitations

- Single repository open at a time — no multi-repo/workspace view yet.
- No merge-conflict resolution UI. A conflicted merge surfaces git's error
  and leaves the conflicting files marked in Changes; resolving them still
  means editing the file outside GitHalls, then staging and committing
  through the app as usual.
- The Jira integration is JQL-driven, not a true multi-column board yet —
  issues are grouped by status in a single sidebar list.
- No stash, tags, or remote-branch management beyond fetch/pull/push yet.

## Contributing

Issues and pull requests are welcome. A few things that keep the project
consistent:

- **No external dependencies.** Everything shells out to the `git` CLI or
  uses `URLSession`/`Foundation`/`Security` directly — no Swift Package
  Manager dependencies. Keep it that way unless there's a strong reason
  not to.
- **One type per file**, grouped by concern (`GIt/`, `Jira/`, `Repository/`,
  `Views/`) — a parser, a model, a service method all live where the
  existing ones of their kind live.
- **Before opening a PR**, run a clean build and the test suite locally
  (commands above) — there's no CI pipeline yet, so a green build on your
  machine is the only signal until there is one.
- New git-layer code should be paired with a console-verifiable path
  (print the parsed result against real `git` output) before it's wired
  into a view — it's the fastest way to catch a parsing edge case before
  it becomes a UI bug.

## License

MIT — see [LICENSE](LICENSE).
