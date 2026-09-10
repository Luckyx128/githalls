//
//  GitService.swift
//  GitHalls
//
//  Created by Lucas de Amorim on 26/08/26.
//

import Foundation

actor GitService {
    struct CommandResult {
        let standardOutput: String
        let standardError: String
        let terminationStatus: Int32
    }
    
    func run(_ arguments: [String], in directory: URL, stdin: String? = nil) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe: Pipe?
        if stdin != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            stdinPipe = pipe
        } else {
            stdinPipe = nil
        }

        defer { withExtendedLifetime((stdoutPipe, stderrPipe)) {} }

        do {
            try process.run()
        } catch {
            throw GitError.failedToLaunch(underlying: error)
        }

        if let stdin, let stdinPipe {
            let handle = stdinPipe.fileHandleForWriting
            try? handle.write(contentsOf: Data(stdin.utf8))
            try? handle.close()
        }

        let stdoutFD = stdoutPipe.fileHandleForReading.fileDescriptor
        let stderrFD = stderrPipe.fileHandleForReading.fileDescriptor
        
        async let stdoutData = Self.readAll(fromFD: stdoutFD)
        async let stderrData = Self.readAll(fromFD: stderrFD)
        async let exitStatus: Int32 = withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        }
        let (outData, errData, status) = try await (stdoutData, stderrData, exitStatus)
        return CommandResult(
            standardOutput: String(decoding: outData, as: UTF8.self),
            standardError: String(decoding: errData, as: UTF8.self),
            terminationStatus: status
        )
    }

    /// The same run, with stdout left as bytes. Decoding a PNG as UTF-8 does not
    /// fail loudly — it quietly replaces every invalid byte — so anything that
    /// wants the file itself has to come through here.
    func runData(_ arguments: [String], in directory: URL) async throws -> (data: Data, terminationStatus: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        defer { withExtendedLifetime((stdoutPipe, stderrPipe)) {} }

        do {
            try process.run()
        } catch {
            throw GitError.failedToLaunch(underlying: error)
        }

        async let stdoutData = Self.readAll(fromFD: stdoutPipe.fileHandleForReading.fileDescriptor)
        async let stderrData = Self.readAll(fromFD: stderrPipe.fileHandleForReading.fileDescriptor)
        async let exitStatus: Int32 = withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        }

        let (outData, _, status) = try await (stdoutData, stderrData, exitStatus)
        return (outData, status)
    }

    private static nonisolated func readAll(fromFD fd: Int32) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
                do {
                    let data = try handle.readToEnd() ?? Data()
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension GitService {
    func stage(at repoURL: URL, path:String) async throws {
        let result = try await run(["add","--" ,path], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }
    
    func unstage(at repoURL: URL, path: String) async throws {
        let result = try await run(["reset", "HEAD", "--", path], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }
    
    func commit(at repoURL: URL, summary: String, description: String?) async throws {
            var arguments = ["commit", "-m", summary]
            if let description, !description.isEmpty {
                arguments += ["-m", description]
            }
            let result = try await run(arguments, in: repoURL)
            guard result.terminationStatus == 0 else {
                throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
            }
        }
    
    func status(at repoURL: URL) async throws -> [FileChange] {
        let result = try await run(["status", "--porcelain=v1", "--untracked-files=all"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return StatusParser.parse(result.standardOutput)
    }

    func numstat(at repoURL: URL) async throws -> [String: (additions: Int, deletions: Int)] {
        let result = try await run(["diff", "--cached", "--numstat"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        var stats: [String: (additions: Int, deletions: Int)] = [:]
        for line in result.standardOutput.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            // Arquivo binário reporta "-\t-\tpath" — sem contagem de linha, ignora.
            guard parts.count == 3, let additions = Int(parts[0]), let deletions = Int(parts[1]) else { continue }
            stats[String(parts[2])] = (additions, deletions)
        }
        return stats
    }
}

extension GitService {
    func diff(at repoURL: URL, for change: FileChange) async throws -> FileDiff {
        guard change.status != .untracked else {
            let fileURL = repoURL.appending(path: change.path)

            // A new image or archive is not text, and reading it as UTF-8
            // throws — which used to surface as an error where a diff belongs.
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                return FileDiff(
                    path: change.path,
                    lines: [DiffLine(kind: .hunkHeader, text: "Binary file not shown",
                                     oldLineNumber: nil, newLineNumber: nil)],
                    isBinary: true
                )
            }

            return DiffParser.syntheticAllAdditions(path: change.path, content: content)
        }

        let result = try await run(["diff", "--no-color", "HEAD", "--", change.path], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return DiffParser.parse(result.standardOutput)
    }
}

extension GitService {
    /// The bytes of a path at a revision — "HEAD", a hash, or "<hash>^".
    ///
    /// Nil when the path is not there: a file that was just added has no
    /// previous revision, and a deleted one has no current one. git says so
    /// with a non-zero exit, which is a normal answer here and not a failure.
    func blob(at repoURL: URL, revision: String, path: String) async throws -> Data? {
        let result = try await runData(["show", "\(revision):\(path)"], in: repoURL)

        return result.terminationStatus == 0 ? result.data : nil
    }

    /// The bytes on disk — the working tree side of a change, which no revision
    /// names.
    func workingTreeBlob(at repoURL: URL, path: String) -> Data? {
        try? Data(contentsOf: repoURL.appending(path: path))
    }
}

extension GitService {
    func identity(at repoURL: URL) async throws -> GitIdentity? {
        async let nameResult = run(["config", "user.name"], in: repoURL)
        async let emailResult = run(["config", "user.email"], in: repoURL)
        let (nameRes, emailRes) = try await (nameResult, emailResult)
        guard nameRes.terminationStatus == 0, emailRes.terminationStatus == 0 else { return nil }
        let name = nameRes.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = emailRes.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || !email.isEmpty else { return nil }
        return GitIdentity(id: UUID(), label: "", name: name, email: email, githubUsername: "")
    }

    func hasLocalIdentity(at repoURL: URL) async throws -> Bool {
        let result = try await run(["config", "--local", "user.name"], in: repoURL)
        return result.terminationStatus == 0
    }

    func setIdentity(at repoURL: URL, name: String, email: String) async throws {
        let nameResult = try await run(["config", "--local", "user.name", name], in: repoURL)
        guard nameResult.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: nameResult.terminationStatus, message: nameResult.standardError)
        }
        let emailResult = try await run(["config", "--local", "user.email", email], in: repoURL)
        guard emailResult.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: emailResult.terminationStatus, message: emailResult.standardError)
        }
    }

    func setRemoteUsername(at repoURL: URL, remoteName: String = "origin", username: String) async throws {
        let currentURL = try await remoteURL(at: repoURL, name: remoteName)
        guard currentURL.hasPrefix("https://") else {
            throw GitError.invalidRemoteURL
        }
        guard let (owner, repo) = GitHubService.ownerAndRepo(fromRemoteURL: currentURL) else {
            throw GitError.invalidRemoteURL
        }
        let newURL = "https://\(username)@github.com/\(owner)/\(repo).git"
        let result = try await run(["remote", "set-url", remoteName, newURL], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    /// Acrescenta o osxkeychain como fallback aos helpers já configurados —
    /// sem resetar a lista. Necessário porque o GitHub CLI (`gh auth
    /// setup-git`) costuma registrar `[credential "https://github.com"]` no
    /// `~/.gitconfig` com um `helper =` vazio (reseta a lista) seguido de
    /// `!gh auth git-credential`, substituindo qualquer osxkeychain
    /// configurado globalmente só pra github.com. O helper do `gh` ignora o
    /// username da URL — sempre resolve pra conta "ativa" no `gh auth
    /// status` — e recusa (exit != 0) quando pedem um username diferente
    /// dessa conta. Sem esse fallback, isso deixava fetch/pull/push
    /// completamente surdos à troca de identidade do GitHalls, sem jeito de
    /// contornar de dentro do app.
    ///
    /// De propósito NÃO resetamos a lista (`-c credential.helper=`) antes
    /// de acrescentar: git só consulta um helper seguinte quando o anterior
    /// não devolve credencial completa, então quem só usa `gh` com uma
    /// conta só nunca chega a bater no osxkeychain — comportamento idêntico
    /// ao de antes. O osxkeychain só entra em jogo quando o(s) helper(s) já
    /// configurados falham ou não têm o que a operação pediu.
    private static let credentialHelperOverride = ["-c", "credential.helper=osxkeychain"]

    func approveCredential(host: String = "github.com", username: String, token: String) async throws {
        let input = "protocol=https\nhost=\(host)\nusername=\(username)\npassword=\(token)\n\n"
        let result = try await run(Self.credentialHelperOverride + ["credential", "approve"], in: FileManager.default.homeDirectoryForCurrentUser, stdin: input)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    func rejectCredential(host: String = "github.com", username: String) async throws {
        let input = "protocol=https\nhost=\(host)\nusername=\(username)\n\n"
        _ = try await run(Self.credentialHelperOverride + ["credential", "reject"], in: FileManager.default.homeDirectoryForCurrentUser, stdin: input)
    }
}

extension GitService {
    func currentBranch(at repoURL: URL) async throws -> String {
        let result = try await run(["branch", "--show-current"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func remoteURL(at repoURL: URL, name: String = "origin") async throws -> String {
        let result = try await run(["remote", "get-url", name], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension GitService {
    func log(at repoURL: URL, limit: Int = 100) async throws -> [Commit] {
        let result = try await run(
            ["log", "--max-count=\(limit)", "--pretty=tformat:\(Self.logFormat)"],
            in: repoURL
        )
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return CommitLogParser.parse(result.standardOutput)
    }

    /// hash, short hash, author, author date, subject.
    private static let logFormat = "%H%x1f%h%x1f%an%x1f%aI%x1f%s%x1e"
}

extension GitService {
    /// The branch a pull request goes into when nobody says otherwise.
    ///
    /// `refs/remotes/origin/HEAD` is what a clone leaves behind pointing at it.
    /// A repository added with `git remote add` never got one, so the usual two
    /// names are tried before giving up — guessing wrong here only means the
    /// sheet opens on "Repository default", which is already the safe answer.
    func defaultBranch(at repoURL: URL, remote: String = "origin") async -> String? {
        if let result = try? await run(["symbolic-ref", "--short", "refs/remotes/\(remote)/HEAD"], in: repoURL),
           result.terminationStatus == 0 {
            let value = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return Branch.remoteShortName(from: value) }
        }
        for candidate in ["main", "master"] {
            if await firstExistingRef(["refs/remotes/\(remote)/\(candidate)"], at: repoURL) != nil {
                return candidate
            }
        }
        return nil
    }

    /// The commits on `head` that `base` does not have.
    ///
    /// Compared against the remote copy of the base where there is one: a local
    /// `main` can be weeks stale, and the pull request is opened against what
    /// the server holds, not against that.
    ///
    /// An empty result also covers a base that does not resolve at all. Both
    /// mean the same thing to the caller — there is nothing here to name the
    /// pull request after.
    func commitsAhead(
        at repoURL: URL,
        base: String,
        head: String,
        remote: String = "origin",
        limit: Int = 100
    ) async throws -> [Commit] {
        guard let baseRef = await firstExistingRef(
            ["refs/remotes/\(remote)/\(base)", "refs/heads/\(base)"],
            at: repoURL
        ) else {
            return []
        }
        let result = try await run(
            ["log", "--max-count=\(limit)", "--pretty=tformat:\(Self.logFormat)", "\(baseRef)..\(head)"],
            in: repoURL
        )
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return CommitLogParser.parse(result.standardOutput)
    }

    private func firstExistingRef(_ candidates: [String], at repoURL: URL) async -> String? {
        for candidate in candidates {
            if let result = try? await run(["rev-parse", "--verify", "--quiet", candidate], in: repoURL),
               result.terminationStatus == 0 {
                return candidate
            }
        }
        return nil
    }
}

extension GitService {
    /// hash, short hash, parents, author, author date, committer date,
    /// decoration, subject.
    private static let graphLogFormat = "%H%x1f%h%x1f%P%x1f%an%x1f%aI%x1f%cI%x1f%D%x1f%s%x1e"

    /// The whole repository, not just the branch that happens to be checked out.
    ///
    /// `--branches --tags --remotes HEAD` is `--all` minus `refs/stash` and
    /// `refs/notes/*` — rows the user never made and the menu cannot act on.
    /// `HEAD` is named explicitly so a detached HEAD still appears in its own
    /// graph.
    ///
    /// `--topo-order`, not `--date-order`: date order interleaves unrelated
    /// branches, and two commits sharing a timestamp can swap between runs,
    /// which reshuffles every lane. Topological order guarantees no parent is
    /// emitted before its children, which is exactly what the lane builder needs.
    ///
    /// `--decorate=full` because with git's short decoration a local branch
    /// named `origin/main` is indistinguishable from the remote-tracking ref.
    /// `--no-color` guards against a `color.ui = always` in the user's config
    /// wrapping ANSI escapes around every decoration.
    /// How far back the graph reaches. `--max-count` stays as a ceiling for a
    /// repository that commits thousands of times in this window.
    private static let graphLogSince = "2.months"

    func graphLog(at repoURL: URL, limit: Int = 1000) async throws -> [GraphCommit] {
        let result = try await run([
            "log",
            "--branches", "--tags", "--remotes", "HEAD",
            "--topo-order",
            "--since=\(Self.graphLogSince)",
            "--max-count=\(limit)",
            "--no-color",
            "--decorate=full",
            "--pretty=tformat:\(Self.graphLogFormat)"
        ], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return CommitGraphParser.parse(result.standardOutput)
    }

    /// The full message, body included. `%s` is one line, and a menu item that
    /// says "Copy Commit Message" while silently dropping the body is a lie.
    func commitMessage(at repoURL: URL, hash: String) async throws -> String {
        let result = try await run(["log", "-1", "--pretty=format:%B", hash], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension GitService {
    /// A merge shows nothing by default: git refuses to pick which parent the
    /// diff is against. Comparing with the first parent is the question a
    /// history view is actually asking — what landed on this branch when the
    /// merge went in — and it is the only form the diff parser understands, the
    /// combined one being a format of its own.
    private static let firstParentMergeDiff = "--diff-merges=first-parent"

    func commitFiles(at repoURL: URL, hash: String) async throws -> [CommitFile] {
        let result = try await run(
            ["show", "--pretty=format:", "--raw", "--numstat", Self.firstParentMergeDiff, hash],
            in: repoURL
        )
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return CommitFileParser.parse(result.standardOutput)
    }

    /// `pathspec` is both sides of a rename where there was one, so git still
    /// reports it as a rename rather than as a file that appeared from nowhere.
    func commitFileDiff(at repoURL: URL, hash: String, pathspec: [String]) async throws -> FileDiff {
        let result = try await run(
            ["show", "--no-color", "--pretty=format:", Self.firstParentMergeDiff, hash, "--"] + pathspec,
            in: repoURL
        )
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return DiffParser.parse(result.standardOutput)
    }
}

extension GitService {
    func discard(at repoURL: URL, change: FileChange) async throws {
        switch change.status {
        case .untracked:
            let result = try await run(["clean", "-f", "--", change.path], in: repoURL)
            guard result.terminationStatus == 0 else {
                throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
            }
        case .added:
            let resetResult = try await run(["reset", "HEAD", "--", change.path], in: repoURL)
            guard resetResult.terminationStatus == 0 else {
                throw GitError.commandFailed(exitCode: resetResult.terminationStatus, message: resetResult.standardError)
            }
            let result = try await run(["clean", "-f", "--", change.path], in: repoURL)
            guard result.terminationStatus == 0 else {
                throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
            }
        case .renamed, .copied:
            let resetResult = try await run(["reset", "HEAD", "--", change.path], in: repoURL)
            guard resetResult.terminationStatus == 0 else {
                throw GitError.commandFailed(exitCode: resetResult.terminationStatus, message: resetResult.standardError)
            }
            let cleanResult = try await run(["clean", "-f", "--", change.path], in: repoURL)
            guard cleanResult.terminationStatus == 0 else {
                throw GitError.commandFailed(exitCode: cleanResult.terminationStatus, message: cleanResult.standardError)
            }
            if let originalPath = change.originalPath {
                let restoreResult = try await run(["checkout", "HEAD", "--", originalPath], in: repoURL)
                guard restoreResult.terminationStatus == 0 else {
                    throw GitError.commandFailed(exitCode: restoreResult.terminationStatus, message: restoreResult.standardError)
                }
            }
        case .unmerged:
            // `checkout HEAD` would write our side and leave the index entry
            // unmerged; `--merge` puts the file back the way the failed merge
            // left it, conflict markers and all.
            //
            // Only while the file really is unmerged, though: `--merge` on a
            // settled path invents a conflict rather than refusing, and the row
            // that triggered this can be a screen the merge has moved past.
            let unmerged = try await run(["ls-files", "--unmerged", "--", change.path], in: repoURL)
            let arguments = unmerged.terminationStatus == 0 && !unmerged.standardOutput.isEmpty
                ? ["checkout", "--merge", "--", change.path]
                : ["checkout", "HEAD", "--", change.path]
            let result = try await run(arguments, in: repoURL)
            guard result.terminationStatus == 0 else {
                throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
            }
        default:
            let result = try await run(["checkout", "HEAD", "--", change.path], in: repoURL)
            guard result.terminationStatus == 0 else {
                throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
            }
        }
    }
}

extension GitService {
    func branches(at repoURL: URL) async throws -> [Branch] {
        let result = try await run(["branch", "-a", "--list"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return BranchParser.parse(result.standardOutput)
    }

    func switchBranch(at repoURL: URL, name: String) async throws {
        let result = try await run(["checkout", name], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    func createBranch(at repoURL: URL, name: String) async throws {
        let result = try await run(["checkout", "-b", name], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }
}

extension GitService {
    /// Park HEAD on a commit without moving any branch.
    func checkoutCommit(at repoURL: URL, hash: String) async throws {
        let result = try await run(["checkout", "--detach", hash], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    /// A branch starting anywhere in the graph. `switchTo` false leaves HEAD
    /// alone — "branch this commit" is often not "go there".
    func createBranch(at repoURL: URL, name: String, startPoint: String, switchTo: Bool) async throws {
        let arguments = switchTo
            ? ["checkout", "-b", name, startPoint]
            : ["branch", name, startPoint]
        let result = try await run(arguments, in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    func renameBranch(at repoURL: URL, from oldName: String, to newName: String) async throws {
        let result = try await run(["branch", "-m", oldName, newName], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    /// `force` is the -D escalation. It is only ever reached through the offer
    /// the caller makes after -d has been refused, never on the first try.
    func deleteLocalBranch(at repoURL: URL, name: String, force: Bool) async throws {
        let result = try await run(["branch", force ? "-D" : "-d", name], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    func deleteRemoteBranch(at repoURL: URL, remote: String = "origin", name: String) async throws {
        let result = try await run(
            Self.credentialHelperOverride + ["push", remote, "--delete", name],
            in: repoURL
        )
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    func pushBranch(at repoURL: URL, branch: String, setUpstream: Bool) async throws {
        let arguments = ["push"] + (setUpstream ? ["-u"] : []) + ["origin", branch]
        let result = try await run(Self.credentialHelperOverride + arguments, in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    /// Brings a branch that is *not* checked out up to date with its remote.
    ///
    /// `git pull origin <branch>` would merge into whatever is checked out
    /// instead — this refspec is the one command that updates the named branch.
    /// It is fast-forward only, and git refusing anything else is the correct
    /// answer: a real merge needs a working tree.
    func fastForwardBranch(at repoURL: URL, remote: String = "origin", branch: String) async throws {
        let result = try await run(
            Self.credentialHelperOverride + ["fetch", remote, "\(branch):\(branch)"],
            in: repoURL
        )
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    func setUpstream(at repoURL: URL, branch: String, upstream: String) async throws {
        let result = try await run(["branch", "--set-upstream-to=\(upstream)", branch], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    /// nil when the branch has no upstream. A non-zero exit is the normal answer
    /// to that question, not a failure worth throwing over.
    func upstream(at repoURL: URL, branch: String) async throws -> String? {
        let result = try await run(["rev-parse", "--abbrev-ref", "\(branch)@{upstream}"], in: repoURL)
        guard result.terminationStatus == 0 else { return nil }
        let name = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

extension GitService {
    func stage(at repoURL: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let result = try await run(["add", "--"] + paths, in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    func unstage(at repoURL: URL, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let result = try await run(["reset", "HEAD", "--"] + paths, in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }
}

extension GitService {
    func fetch(at repoURL: URL) async throws {
        let result = try await run(Self.credentialHelperOverride + ["fetch"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    func pull(at repoURL: URL) async throws {
        let result = try await run(Self.credentialHelperOverride + ["pull"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    /// Pull on a branch that is also ahead. Since git 2.27 a plain `git pull`
    /// aborts on divergent branches when the reconciliation is not configured
    /// ("Need to specify how to reconcile divergent branches"), so a merge is
    /// asked for explicitly — but only when the user set no preference of their
    /// own, which is theirs to keep.
    func pullDivergent(at repoURL: URL) async throws {
        let arguments = ["pull"] + (try await reconcileArguments(at: repoURL))

        let result = try await run(Self.credentialHelperOverride + arguments, in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    /// Sets the working tree aside for the pull and puts it back afterwards,
    /// which is what git refuses to do on its own when the merge would write
    /// over uncommitted work.
    ///
    /// - Returns: true when the pull landed but those changes could not be put
    ///   back cleanly. git reports that on stderr **while exiting 0**, so it has
    ///   to be read out rather than thrown.
    @discardableResult
    func pullAutostash(at repoURL: URL) async throws -> Bool {
        let arguments = ["pull", "--autostash"] + (try await reconcileArguments(at: repoURL))

        let result = try await run(Self.credentialHelperOverride + arguments, in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }

        return PullDiagnostics.autostashConflicted(result.standardError + result.standardOutput)
    }

    /// `--no-rebase`, but only when the user configured no preference of their
    /// own. Without it a divergent pull aborts asking to be told how.
    private func reconcileArguments(at repoURL: URL) async throws -> [String] {
        var configured = try await configValue("pull.rebase", at: repoURL)
        if configured == nil {
            configured = try await configValue("pull.ff", at: repoURL)
        }

        return configured == nil ? ["--no-rebase"] : []
    }

    /// `git config <key>` exits non-zero when the key is unset, which is a
    /// normal answer here and not a failure.
    private func configValue(_ key: String, at repoURL: URL) async throws -> String? {
        let result = try await run(["config", key], in: repoURL)
        guard result.terminationStatus == 0 else { return nil }

        let value = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func push(at repoURL: URL, branch: String) async throws {
        let result = try await run(Self.credentialHelperOverride + ["push", "-u", "origin", branch], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }
}

extension GitService {
    func branchSync(at repoURL: URL) async throws -> (ahead: Int, behind: Int)? {
        let result = try await run(["status", "--porcelain=v2", "--branch"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        for line in result.standardOutput.split(separator: "\n") {
            guard line.hasPrefix("# branch.ab ") else { continue }
            let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
            guard parts.count == 2, let ahead = Int(parts[0]), let behindRaw = Int(parts[1]) else { continue }
            return (ahead, abs(behindRaw))
        }
        return nil // sem upstream configurado (branch nova, nunca publicada)
    }
}
extension GitService {
    func merge(at repoURL: URL, branch: String) async throws {
        let result = try await run(["merge", branch], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }
}

extension GitService {
    func clone(url: String, into destinationURL: URL) async throws {
        let parent = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let result = try await run(Self.credentialHelperOverride + ["clone", url, destinationURL.path], in: parent)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }
}

extension GitService {
    static func repositoryName(fromCloneURL urlString: String) -> String {
        var name = urlString.trimmingCharacters(in: .whitespaces)
        while name.hasSuffix("/") { name.removeLast() }
        if name.hasSuffix(".git") { name.removeLast(4) }
        let separators = CharacterSet(charactersIn: "/:")
        return name.components(separatedBy: separators).last ?? name
    }
}

// MARK: - Merge in progress

extension GitService {
    /// The open merge, or nil when there is none.
    ///
    /// `git status` cannot answer this: once every conflict is resolved and
    /// staged it reports a clean tree, which is exactly when the app most needs
    /// to know a merge is still waiting to be committed. `MERGE_HEAD` is the
    /// thing that survives that.
    func mergeState(at repoURL: URL) async throws -> MergeState? {
        let head = try await run(["rev-parse", "--verify", "--quiet", "MERGE_HEAD"], in: repoURL)
        guard head.terminationStatus == 0 else { return nil }

        let unmerged = try await run(["ls-files", "--unmerged"], in: repoURL)
        guard unmerged.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: unmerged.terminationStatus, message: unmerged.standardError)
        }

        // `diff --check` exits 2 when it finds something — the normal exit-code
        // guard would turn a useful answer into an error.
        let worktreeCheck = try await run(["diff", "--check"], in: repoURL)
        let stagedCheck = try await run(["diff", "--check", "--cached"], in: repoURL)
        var markers = MergeStateParser.conflictMarkerPaths(worktreeCheck.standardOutput)
        for path in MergeStateParser.conflictMarkerPaths(stagedCheck.standardOutput) where !markers.contains(path) {
            markers.append(path)
        }

        return MergeState(
            unresolvedPaths: MergeStateParser.unmergedPaths(unmerged.standardOutput),
            markerPaths: markers,
            preparedMessage: try? await mergeMessage(at: repoURL)
        )
    }

    /// The message git prepared for the merge commit.
    private func mergeMessage(at repoURL: URL) async throws -> String? {
        let result = try await run(["rev-parse", "--git-path", "MERGE_MSG"], in: repoURL)
        guard result.terminationStatus == 0 else { return nil }

        let relative = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relative.isEmpty else { return nil }

        // `--git-path` answers relative to the repository root for a normal
        // checkout, absolute for a worktree or a separate git dir.
        let fileURL = relative.hasPrefix("/")
            ? URL(filePath: relative)
            : repoURL.appending(path: relative)

        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    func abortMerge(at repoURL: URL) async throws {
        let result = try await run(["merge", "--abort"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    /// Finishes the open merge. A nil summary keeps the message git prepared.
    func commitMerge(at repoURL: URL, summary: String?, description: String?) async throws {
        var arguments = ["commit"]
        if let summary, !summary.isEmpty {
            arguments += ["-m", summary]
            if let description, !description.isEmpty {
                arguments += ["-m", description]
            }
        } else {
            arguments.append("--no-edit")
        }

        let result = try await run(arguments, in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }
}
