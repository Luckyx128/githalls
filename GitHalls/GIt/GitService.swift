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
    
    func run(_ arguments: [String], in directory: URL) async throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        do {
            try process.run()
        } catch {
            throw GitError.failedToLaunch(underlying: error)
        }
        
        async let stdoutData = Self.readAll(stdoutPipe.fileHandleForReading)
        async let stderrData = Self.readAll(stderrPipe.fileHandleForReading)
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
    
    private static func readAll(_ handle: FileHandle) async throws -> Data {
            var data = Data()
            for try await byte in handle.bytes { data.append(byte) }
            return data
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
}

extension GitService {
    func diff(at repoURL: URL, for change: FileChange) async throws -> FileDiff {
        guard change.status != .untracked else {
            let fileURL = repoURL.appending(path: change.path)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
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
    func currentBranch(at repoURL: URL) async throws -> String {
        let result = try await run(["branch", "--show-current"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension GitService {
    func log(at repoURL: URL, limit: Int = 100) async throws -> [Commit] {
        let format = "%H%x1f%h%x1f%an%x1f%aI%x1f%s%x1e"
        let result = try await run(["log", "--max-count=\(limit)", "--pretty=tformat:\(format)"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return CommitLogParser.parse(result.standardOutput)
    }
}

extension GitService {
    func changedPaths(at repoURL: URL, hash: String) async throws -> [String] {
        let result = try await run(["show", "--pretty=format:", "--name-only", hash], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return result.standardOutput
            .split(separator: "\n")
            .map(String.init)
    }

    func commitFileDiff(at repoURL: URL, hash: String, path: String) async throws -> FileDiff {
        let result = try await run(["show", "--no-color", "--pretty=format:", hash, "--", path], in: repoURL)
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
            // O path novo não existe no HEAD (só o antigo) — "checkout HEAD -- path" falharia.
            // Desfaz o rename: descarta o path novo e restaura o conteúdo original no path antigo.
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
        let result = try await run(["branch", "--list"], in: repoURL)
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
        let result = try await run(["fetch"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    func pull(at repoURL: URL) async throws {
        let result = try await run(["pull"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
    }

    func push(at repoURL: URL, branch: String) async throws {
        let result = try await run(["push", "-u", "origin", branch], in: repoURL)
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
