//
//  PodfileEditor.swift
//  PkgLiftMigration
//

import Foundation
import PkgLiftCocoaPods

/// Conservative Podfile modification
public struct PodfileEditor: Sendable {

    public struct EditResult: Sendable, Equatable {
        public let content: String
        public let removedPods: Set<String>

        public init(content: String, removedPods: Set<String>) {
            self.content = content
            self.removedPods = removedPods
        }
    }
    
    public init() {}
    
    public func remove(pods: Set<String>, from podfileContent: String) -> String {
        removeWithResult(pods: pods, from: podfileContent).content
    }

    /// Removes only exact, statically declared pod lines and reports what was found.
    /// Target blocks and all unrelated Ruby are always preserved.
    public func removeWithResult(pods: Set<String>, from podfileContent: String) -> EditResult {
        // Use the same declaration evidence as analysis. This preserves Ruby
        // comments/data sections and recognizes every supported literal form.
        let parsed = PodfileParser().parse(content: podfileContent)
        var removedLines: Set<Int> = []
        var removedPods: Set<String> = []
        for dependency in parsed.directDependencies where pods.contains(dependency.name) {
            guard dependency.source == .registry else { continue }
            for declaration in dependency.declarations ?? [] {
                removedLines.insert(declaration.line)
                removedPods.insert(dependency.name)
            }
        }
        // Match the parser's physical LF lines, retaining CRLF and the final
        // newline exactly on every untouched line.
        let lines = podfileContent.unicodeScalars.split(
            omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" }
        ).map(String.init)
        let content = lines.enumerated()
            .filter { !removedLines.contains($0.offset + 1) }
            .map(\.element)
            .joined(separator: "\n")
        return EditResult(content: content, removedPods: removedPods)
    }

    public func removeWithBackup(pods: Set<String>, podfile: URL, backupDir: URL) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: backupDir.path) {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        }
        let backupFile = backupDir.appendingPathComponent("Podfile.backup")
        if fm.fileExists(atPath: backupFile.path) {
            try fm.removeItem(at: backupFile)
        }
        try fm.copyItem(at: podfile, to: backupFile)
        
        let content = try String(contentsOf: podfile, encoding: .utf8)
        let modified = remove(pods: pods, from: content)
        try modified.write(to: podfile, atomically: true, encoding: .utf8)
    }
}
