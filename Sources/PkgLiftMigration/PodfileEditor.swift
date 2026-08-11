//
//  PodfileEditor.swift
//  PkgLiftMigration
//

import Foundation

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
        let lines = podfileContent.components(separatedBy: .newlines)
        var newLines = [String]()
        var removedPods: Set<String> = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("pod ") {
                let podDeclaration = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                let firstQuoteIndex = podDeclaration.firstIndex(where: { $0 == "'" || $0 == "\"" })
                
                if let quote = firstQuoteIndex {
                    let quoteChar = podDeclaration[quote]
                    let afterFirstQuote = podDeclaration[podDeclaration.index(after: quote)...]
                    if let secondQuote = afterFirstQuote.firstIndex(of: quoteChar) {
                        let podName = String(afterFirstQuote[..<secondQuote])
                        if pods.contains(podName) {
                            removedPods.insert(podName)
                            continue // Remove pod
                        }
                    }
                }
                
            }
            
            newLines.append(line)
        }
        
        return EditResult(content: newLines.joined(separator: "\n"), removedPods: removedPods)
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
