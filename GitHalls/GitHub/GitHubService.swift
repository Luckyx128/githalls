//
//  GitHubService.swift
//  GitHalls
//

import Foundation

/// Wrapper do `gh` CLI, mesmo padrão do GitService — actor, Process,
/// drenagem em bloco dos pipes (não byte-a-byte).
actor GitHubService {
    /// Remembered working login per "owner/repo". Logins only, never tokens.
    private static let accountDefaultsKey = "githubAccountByRepo"

    /// Tokens live in memory for the app session and are never persisted.
    private var tokens: [String: String] = [:]
    private var knownLogins: [String]?

    struct CommandResult {
        let standardOutput: String
        let standardError: String
        let terminationStatus: Int32
    }

    /// Runs `gh`, and if the active account cannot see the repository, retries
    /// with the other logged-in accounts (via GH_TOKEN, so `gh`'s own active
    /// account is never switched). The account that works is remembered per
    /// repository. If none works, the first failure is returned.
    func run(_ arguments: [String], in directory: URL) async throws -> CommandResult {
        let remembered = rememberedLogin(in: directory)
        let firstTry = remembered
        let original = try await attempt(arguments, in: directory, as: firstTry)
        if original.terminationStatus == 0 || !GitHubAccounts.isAccessError(original.standardError) {
            if original.terminationStatus == 0 { remember(firstTry, in: directory) }
            return original
        }

        // Only now pay for listing the accounts.
        let logins = await loginList()
        for login in GitHubAccounts.attemptOrder(logins: logins, remembered: remembered) where login != firstTry {
            let result = try await attempt(arguments, in: directory, as: login)
            if result.terminationStatus == 0 {
                remember(login, in: directory)
                return result
            }
            if !GitHubAccounts.isAccessError(result.standardError) { return result }
        }
        return original
    }

    /// One run as `login`, or as gh's active account when `login` is nil. A
    /// login whose token cannot be fetched runs as the active account instead.
    private func attempt(_ arguments: [String], in directory: URL, as login: String?) async throws -> CommandResult {
        let token = if let login { await token(for: login) } else { String?.none }
        return try await execute(arguments, in: directory, token: token)
    }

    private func loginList() async -> [String] {
        if let knownLogins { return knownLogins }
        guard let result = try? await execute(["auth", "status", "--json", "hosts"], in: FileManager.default.temporaryDirectory, token: nil) else {
            return []
        }
        // Older gh has no --json; its text output goes to stderr on some versions.
        var logins = GitHubAccounts.logins(fromStatusOutput: result.standardOutput)
        if logins.isEmpty,
           let text = try? await execute(["auth", "status"], in: FileManager.default.temporaryDirectory, token: nil) {
            logins = GitHubAccounts.logins(fromStatusOutput: text.standardOutput + "\n" + text.standardError)
        }
        if !logins.isEmpty { knownLogins = logins }
        return logins
    }

    private func token(for login: String) async -> String? {
        if let cached = tokens[login] { return cached }
        guard let result = try? await execute(["auth", "token", "--user", login], in: FileManager.default.temporaryDirectory, token: nil),
              result.terminationStatus == 0 else { return nil }
        let token = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        tokens[login] = token
        return token
    }

    private func repoKey(in directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "remote", "get-url", "origin"]
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let parsed = Self.ownerAndRepo(fromRemoteURL: String(decoding: data, as: UTF8.self))
        else { return nil }
        return "\(parsed.owner)/\(parsed.repo)".lowercased()
    }

    private func rememberedLogin(in directory: URL) -> String? {
        guard let key = repoKey(in: directory) else { return nil }
        let map = UserDefaults.standard.dictionary(forKey: Self.accountDefaultsKey) as? [String: String]
        return map?[key]
    }

    /// Stores the login that worked (nil clears it: the active account works).
    private func remember(_ login: String?, in directory: URL) {
        guard let key = repoKey(in: directory) else { return }
        var map = (UserDefaults.standard.dictionary(forKey: Self.accountDefaultsKey) as? [String: String]) ?? [:]
        guard map[key] != login else { return }
        map[key] = login
        UserDefaults.standard.set(map, forKey: Self.accountDefaultsKey)
    }

    private func execute(_ arguments: [String], in directory: URL, token: String?) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments
        process.currentDirectoryURL = directory

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

extension GitHubService {
    /// Confere se o `gh` está instalado e acessível, sem lançar erro.
    func isAvailable() async -> Bool {
        guard let result = try? await run(["--version"], in: FileManager.default.temporaryDirectory) else {
            return false
        }
        return result.terminationStatus == 0
    }

    /// Cria o PR e devolve a URL dele (o `gh pr create` imprime a URL no
    /// stdout quando roda com --title/--body, sem precisar de terminal
    /// interativo).
    func createPullRequest(at repoURL: URL, title: String, body: String, base: String?) async throws -> String {
        var arguments = ["pr", "create", "--title", title, "--body", body]
        if let base, !base.isEmpty {
            arguments += ["--base", base]
        }
        let result = try await run(arguments, in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension GitHubService {
    /// Extrai "owner" e "repo" de uma URL de remote do GitHub, cobrindo tanto
    /// HTTPS ("https://github.com/owner/repo.git") quanto SSH
    /// ("git@github.com:owner/repo.git").
    static func ownerAndRepo(fromRemoteURL urlString: String) -> (owner: String, repo: String)? {
        var text = urlString.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix(".git") { text.removeLast(4) }
        guard let range = text.range(of: "github.com") else { return nil }
        let after = text[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: ":/"))
        let parts = after.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    /// Monta a URL de criação de PR no site do GitHub, pré-preenchida —
    /// usada quando o `gh` CLI não está disponível. Sem "base" explícito,
    /// usa "/pull/new/<head>" (o GitHub escolhe a branch padrão do repo
    /// sozinho), igual o caminho via CLI faz quando --base não é passado.
    static func pullRequestBrowserURL(
        owner: String,
        repo: String,
        head: String,
        base: String?,
        title: String,
        body: String
    ) -> URL? {
        let path: String
        if let base, !base.isEmpty {
            path = "https://github.com/\(owner)/\(repo)/compare/\(base)...\(head)"
        } else {
            path = "https://github.com/\(owner)/\(repo)/pull/new/\(head)"
        }
        var components = URLComponents(string: path)
        components?.queryItems = [
            URLQueryItem(name: "quick_pull", value: "1"),
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }
}

extension GitHubService {
    /// The open pull request whose head is `head`, if there is one.
    ///
    /// Silent about every failure: no `gh`, not signed in, not a GitHub remote.
    /// This only exists to spare the user from filling in a form for a pull
    /// request that already exists, and none of those are worth an alert in
    /// front of the form they asked for.
    func openPullRequest(at repoURL: URL, head: String) async -> PullRequestSummary? {
        guard let result = try? await run(
            ["pr", "list", "--head", head, "--state", "open", "--limit", "1", "--json", "number,title,url"],
            in: repoURL
        ), result.terminationStatus == 0 else {
            return nil
        }
        let data = Data(result.standardOutput.utf8)
        return (try? JSONDecoder().decode([PullRequestSummary].self, from: data))?.first
    }
}
