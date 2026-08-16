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

    /// Whether a root-level Cartfile was found without reading its contents.
    public let hasCartfile: Bool

    /// Whether a root-level Cartfile.resolved was found without reading its contents.
    public let hasCartfileResolved: Bool

    public init(
        rootPath: String,
        podfilePath: String?,
        podfileLockPath: String?,
        manifestLockPath: String?,
        projectPaths: [String],
        workspacePaths: [String],
        configPath: String?,
        localRegistryPath: String?,
        hasCartfile: Bool = false,
        hasCartfileResolved: Bool = false
    ) {
        self.rootPath = rootPath
        self.podfilePath = podfilePath
        self.podfileLockPath = podfileLockPath
        self.manifestLockPath = manifestLockPath
        self.projectPaths = projectPaths
        self.workspacePaths = workspacePaths
        self.configPath = configPath
        self.localRegistryPath = localRegistryPath
        self.hasCartfile = hasCartfile
        self.hasCartfileResolved = hasCartfileResolved
    }

    /// Whether any CocoaPods files were found.
    public var hasCocoaPods: Bool {
        podfilePath != nil || podfileLockPath != nil
    }

    /// Whether any Xcode project files were found.
    public var hasXcodeProject: Bool {
        !projectPaths.isEmpty
    }

    /// Whether root-level Carthage metadata was found.
    public var hasCarthageFiles: Bool {
        hasCartfile || hasCartfileResolved
    }
}

// MARK: - File Discovery

/// Discovers project files in a directory.
///
/// This does NOT follow symlinks outside the project directory
/// to prevent path traversal attacks.
public struct FileDiscovery: Sendable {
    private static let skippedDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "carthage",
        "deriveddata",
        "pods",
    ]

    public init() {}

    /// Discover relevant project files in the given directory.
    ///
    /// - Parameter path: The project root directory to scan.
    /// - Returns: Discovered files.
    /// - Throws: If the path does not exist or is not a directory.
    public func discover(in path: String) throws -> DiscoveredFiles {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: path, isDirectory: true)
            .standardized
            .resolvingSymlinksInPath()

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
        let hasCartfile = isRegularFile(named: "Cartfile", in: rootPath)
        let hasCartfileResolved = isRegularFile(named: "Cartfile.resolved", in: rootPath)

        // Discover directories
        let localRegistryPath: String? = {
            let path = (rootPath as NSString).appendingPathComponent(".pkglift/registry")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return path
            }
            return nil
        }()

        // Find Xcode projects and workspaces recursively without entering
        // generated dependency trees or Xcode package directories.
        let projectPaths = findItems(withExtension: "xcodeproj", in: rootPath)
        let workspacePaths = findItems(withExtension: "xcworkspace", in: rootPath)

        return DiscoveredFiles(
            rootPath: rootPath,
            podfilePath: podfilePath,
            podfileLockPath: podfileLockPath,
            manifestLockPath: manifestLockPath,
            projectPaths: projectPaths,
            workspacePaths: workspacePaths,
            configPath: configPath,
            localRegistryPath: localRegistryPath,
            hasCartfile: hasCartfile,
            hasCartfileResolved: hasCartfileResolved
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

        return resolvedPath
    }

    private func isRegularFile(named name: String, in directory: String) -> Bool {
        guard let path = findFile(named: name, in: directory) else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private func findItems(withExtension ext: String, in directory: String) -> [String] {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: directory, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardized
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .nameKey]

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var matches: Set<String> = []

        for case let itemURL as URL in enumerator {
            guard let values = try? itemURL.resourceValues(forKeys: Set(resourceKeys)) else {
                enumerator.skipDescendants()
                continue
            }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }

            guard values.isDirectory == true else { continue }

            let directoryName = (values.name ?? itemURL.lastPathComponent).lowercased()
            if Self.skippedDirectoryNames.contains(directoryName) {
                enumerator.skipDescendants()
                continue
            }

            let resolved = itemURL.resolvingSymlinksInPath().standardized
            guard Self.isContained(resolved.path, in: rootURL.path) else {
                enumerator.skipDescendants()
                continue
            }

            let pathExtension = resolved.pathExtension
            if pathExtension == "xcodeproj" || pathExtension == "xcworkspace" {
                if pathExtension == ext {
                    matches.insert(resolved.path)
                }
                enumerator.skipDescendants()
            }
        }

        return matches.sorted()
    }

    private static func isContained(_ path: String, in rootPath: String) -> Bool {
        if rootPath == "/" { return path.hasPrefix("/") }
        return path == rootPath || path.hasPrefix(rootPath + "/")
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
