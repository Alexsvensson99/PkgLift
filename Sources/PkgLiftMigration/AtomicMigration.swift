//
//  AtomicMigration.swift
//  PkgLiftMigration
//

import Foundation

/// Transaction-like migration
public struct AtomicMigration: Sendable {
    
    public enum MigrationError: Error, LocalizedError {
        case actionFailed(underlyingError: Error)
        
        public var errorDescription: String? {
            switch self {
            case .actionFailed(let err):
                return "Migration failed and was rolled back. Underlying error: \(err.localizedDescription)"
            }
        }
    }

    public init() {}
    
    /// Copies files to a backup directory, performs the action, and rolls back if the action fails.
    public func perform(files: [URL], backupDir: URL, action: () throws -> Void) throws {
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: backupDir.path) {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        }
        
        var backedUpFiles = [(original: URL, backup: URL)]()
        
        for file in files {
            let backupFile = backupDir.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: backupFile.path) {
                try fm.removeItem(at: backupFile)
            }
            if fm.fileExists(atPath: file.path) {
                try fm.copyItem(at: file, to: backupFile)
                backedUpFiles.append((original: file, backup: backupFile))
            }
        }
        
        do {
            try action()
        } catch {
            for backup in backedUpFiles {
                if fm.fileExists(atPath: backup.original.path) {
                    try fm.removeItem(at: backup.original)
                }
                if fm.fileExists(atPath: backup.backup.path) {
                    try fm.copyItem(at: backup.backup, to: backup.original)
                }
            }
            throw MigrationError.actionFailed(underlyingError: error)
        }
    }
}
