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
