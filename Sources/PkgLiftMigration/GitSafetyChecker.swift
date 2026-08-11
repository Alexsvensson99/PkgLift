//
//  GitSafetyChecker.swift
//  PkgLiftMigration
//

import Foundation
import PkgLiftCore

public struct GitSafetyResult: Sendable, Equatable {
    public let isRepository: Bool
    public let isClean: Bool
    public let changedFiles: [String]
    
    public init(isRepository: Bool, isClean: Bool, changedFiles: [String]) {
        self.isRepository = isRepository
        self.isClean = isClean
        self.changedFiles = changedFiles
    }
}

public enum GitSafetyError: LocalizedError, Sendable {
    case statusFailed(String)

    public var errorDescription: String? {
        switch self {
        case .statusFailed(let detail):
            return "Could not determine Git working-tree safety: \(detail)"
        }
    }
}

/// Checks Git working tree state
public struct GitSafetyChecker: Sendable {
    private let processRunner = ProcessRunner()

    public init() {}
    
    public func check(directory: URL) throws -> GitSafetyResult {
        let executable = "/usr/bin/git"
        let args = ["-C", directory.path, "status", "--porcelain"]

        let result = try processRunner.run(executable: executable, arguments: args)
        if result.exitCode != 0 {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 128 && detail.lowercased().contains("not a git repository") {
                return GitSafetyResult(isRepository: false, isClean: true, changedFiles: [])
            }
            throw GitSafetyError.statusFailed(detail.isEmpty ? "git status exited with code \(result.exitCode)" : detail)
        }
        
        let lines = result.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        if lines.isEmpty {
            return GitSafetyResult(isRepository: true, isClean: true, changedFiles: [])
        } else {
            let changedFiles = lines.compactMap { line -> String? in
                guard line.count > 3 else { return nil }
                let start = line.index(line.startIndex, offsetBy: 3)
                return String(line[start...])
            }
            return GitSafetyResult(isRepository: true, isClean: false, changedFiles: changedFiles)
        }
    }
}
