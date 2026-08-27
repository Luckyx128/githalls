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
    func status(at repoURL: URL) async throws -> [FileChange] {
        let result = try await run(["status", "--porcelain=v1", "--untracked-files=all"], in: repoURL)
        guard result.terminationStatus == 0 else {
            throw GitError.commandFailed(exitCode: result.terminationStatus, message: result.standardError)
        }
        return StatusParser.parse(result.standardOutput)
    }
}
