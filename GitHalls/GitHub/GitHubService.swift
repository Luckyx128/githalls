//
//  GitHubService.swift
//  GitHalls
//

import Foundation

/// Wrapper do `gh` CLI, mesmo padrão do GitService — actor, Process,
/// drenagem em bloco dos pipes (não byte-a-byte).
actor GitHubService {
    struct CommandResult {
        let standardOutput: String
        let standardError: String
        let terminationStatus: Int32
    }

    func run(_ arguments: [String], in directory: URL) async throws -> CommandResult {
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
