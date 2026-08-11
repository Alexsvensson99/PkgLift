// PkgLiftCore/FileDiscovery.swift
// Discovers project files relevant to PkgLift analysis.

import Foundation

// MARK: - Discovered Project Files

/// Files discovered in a project directory relevant to PkgLift.
public struct DiscoveredFiles: Sendable {
    /// The root directory that was scanned.
    public let rootPath: String

    /// Podfile path, if found.
    public let podfilePath: String?

    /// Podfile.lock path, if found.
    public let podfileLockPath: String?

    /// Pods/Manifest.lock path, if found.
    public let manifestLockPath: String?

    /// Xcode project paths (.xcodeproj).
    public let projectPaths: [String]

    /// Xcode workspace paths (.xcworkspace).
    public let workspacePaths: [String]

    /// PkgLift configuration file path, if found.
    public let configPath: String?

    /// Local registry override directory, if found.
    public let localRegistryPath: String?

    /// Whether any CocoaPods files were found.
    public var hasCocoaPods: Bool {
        podfilePath != nil || podfileLockPath != nil
    }

    /// Whether any Xcode project files were found.
    public var hasXcodeProject: Bool {
        !projectPaths.isEmpty
    }
}

// MARK: - File Discovery

/// Discovers project files in a directory.
///
/// This does NOT follow symlinks outside the project directory
/// to prevent path traversal attacks.
public struct FileDiscovery: Sendable {
    public init() {}

    /// Discover relevant project files in the given directory.
    ///
    /// - Parameter path: The project root directory to scan.
    /// - Returns: Discovered files.
    /// - Throws: If the path does not exist or is not a directory.
    public func discover(in path: String) throws -> DiscoveredFiles {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: path).standardized

        // Validate the path exists and is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw FileDiscoveryError.notADirectory(path)
        }

        let rootPath = rootURL.path

        // Discover files
        let podfilePath = findFile(named: "Podfile", in: rootPath)
        let podfileLockPath = findFile(named: "Podfile.lock", in: rootPath)
        let manifestLockPath = findFile(
            named: "Manifest.lock", in: (rootPath as NSString).appendingPathComponent("Pods"))
        let configPath = findFile(named: ".pkglift.yml", in: rootPath)

        // Discover directories
        let localRegistryPath: String? = {
            let path = (rootPath as NSString).appendingPathComponent(".pkglift/registry")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return path
            }
            return nil
        }()

        // Find Xcode projects and workspaces (only in root, not recursive)
        let projectPaths = findItems(withExtension: "xcodeproj", in: rootPath)
        let workspacePaths = findItems(withExtension: "xcworkspace", in: rootPath)
            .filter { !$0.contains("/Pods/") }  // Exclude CocoaPods-generated workspaces in Pods/

        return DiscoveredFiles(
            rootPath: rootPath,
            podfilePath: podfilePath,
            podfileLockPath: podfileLockPath,
            manifestLockPath: manifestLockPath,
            projectPaths: projectPaths,
            workspacePaths: workspacePaths,
            configPath: configPath,
            localRegistryPath: localRegistryPath
        )
    }

    // MARK: - Private Helpers

    private func findFile(named name: String, in directory: String) -> String? {
        let path = (directory as NSString).appendingPathComponent(name)
        let fileManager = FileManager.default

        // Security: check that the resolved path is still within the directory
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized.path
        let resolvedDir = URL(fileURLWithPath: directory).resolvingSymlinksInPath().standardized.path

        guard resolvedPath == resolvedDir || resolvedPath.hasPrefix(resolvedDir + "/") else { return nil }

        guard fileManager.fileExists(atPath: path) else { return nil }

        return path
    }

    private func findItems(withExtension ext: String, in directory: String) -> [String] {
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return []
        }

        return contents
            .filter { ($0 as NSString).pathExtension == ext }
            .map { (directory as NSString).appendingPathComponent($0) }
            .sorted()
    }
}

// MARK: - Errors

/// Errors during file discovery.
public enum FileDiscoveryError: Error, LocalizedError, Sendable {
    case notADirectory(String)
    case pathTraversal(String)

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let path):
            return "Not a directory: \(path)"
        case .pathTraversal(let path):
            return "Potential path traversal detected: \(path)"
        }
    }
}
