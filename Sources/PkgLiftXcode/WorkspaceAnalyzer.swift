// PkgLiftXcode/WorkspaceAnalyzer.swift
// Analyzes Xcode workspaces using XcodeProj.

import Foundation
import PathKit
import PkgLiftCore
import XcodeProj

/// Errors that can occur during Xcode workspace analysis.
public enum WorkspaceAnalyzerError: Error, LocalizedError, Sendable {
    case workspaceNotFound(String)
    case invalidWorkspace(String)
    case workspaceOutsideRoot(workspace: String, root: String)
    case projectReferenceOutsideRoot(reference: String, resolved: String, root: String)
    case unsupportedLocationScheme(String)
    case invalidAbsoluteLocation(String)

    public var errorDescription: String? {
        switch self {
        case .workspaceNotFound(let path):
            return "Xcode workspace not found at path: \(path)"
        case .invalidWorkspace(let path):
            return "Invalid or corrupted Xcode workspace at path: \(path)"
        case .workspaceOutsideRoot(let workspace, let root):
            return "Workspace '\(workspace)' is outside the selected root '\(root)'."
        case .projectReferenceOutsideRoot(let reference, let resolved, let root):
            return "Workspace project reference '\(reference)' resolves to '\(resolved)', outside the selected root '\(root)'."
        case .unsupportedLocationScheme(let scheme):
            return "Workspace project reference uses unsupported location scheme '\(scheme)'."
        case .invalidAbsoluteLocation(let location):
            return "Workspace absolute project reference is not an absolute path: \(location)"
        }
    }
}

/// Result of a workspace analysis.
public struct WorkspaceAnalysisResult: Sendable {
    /// Canonical absolute paths for non-Pods projects referenced by the workspace.
    public let projectPaths: [String]
    public let isCocoaPodsGenerated: Bool

    public init(projectPaths: [String], isCocoaPodsGenerated: Bool) {
        self.projectPaths = projectPaths
        self.isCocoaPodsGenerated = isCocoaPodsGenerated
    }
}

/// Main analyzer for Xcode workspaces.
public struct WorkspaceAnalyzer: Sendable {
    public init() {}

    /// Analyzes an Xcode workspace at the given path.
    ///
    /// Relative workspace references are resolved according to their Xcode
    /// location scheme. Every project reference must stay within `rootPath`
    /// after standardization and symlink resolution.
    ///
    /// - Parameters:
    ///   - path: The path to the `.xcworkspace` directory.
    ///   - rootPath: The containment root. Defaults to the workspace's parent.
    /// - Returns: Canonical absolute non-Pods project paths.
    /// - Throws: If the workspace is invalid or a project reference escapes the root.
    public func analyzeWorkspace(
        at path: String,
        containedIn rootPath: String? = nil
    ) throws -> WorkspaceAnalysisResult {
        let workspaceURL = URL(fileURLWithPath: path, isDirectory: true)
            .standardized
            .resolvingSymlinksInPath()
        let workspacePath = Path(workspaceURL.path)
        guard workspacePath.exists else {
            throw WorkspaceAnalyzerError.workspaceNotFound(path)
        }

        let workspaceDirectory = workspaceURL.deletingLastPathComponent()
        let rootURL = URL(
            fileURLWithPath: rootPath ?? workspaceDirectory.path,
            isDirectory: true
        )
        .standardized
        .resolvingSymlinksInPath()

        guard Self.isContained(workspaceURL.path, in: rootURL.path) else {
            throw WorkspaceAnalyzerError.workspaceOutsideRoot(
                workspace: workspaceURL.path,
                root: rootURL.path
            )
        }

        let workspace: XCWorkspace
        do {
            workspace = try XCWorkspace(pathString: workspaceURL.path)
        } catch {
            throw WorkspaceAnalyzerError.invalidWorkspace(workspaceURL.path)
        }

        var projectPaths: Set<String> = []
        var isCocoaPodsGenerated = false

        for element in workspace.data.children {
            try collectProjects(
                from: element,
                groupBase: workspaceDirectory,
                containerBase: workspaceDirectory,
                rootURL: rootURL,
                projectPaths: &projectPaths,
                isCocoaPodsGenerated: &isCocoaPodsGenerated
            )
        }

        return WorkspaceAnalysisResult(
            projectPaths: projectPaths.sorted(),
            isCocoaPodsGenerated: isCocoaPodsGenerated
        )
    }

    private func collectProjects(
        from element: XCWorkspaceDataElement,
        groupBase: URL,
        containerBase: URL,
        rootURL: URL,
        projectPaths: inout Set<String>,
        isCocoaPodsGenerated: inout Bool
    ) throws {
        switch element {
        case .file(let fileReference):
            let isSelfProjectReference: Bool
            if case .current(let path) = fileReference.location {
                isSelfProjectReference = path.isEmpty && containerBase.pathExtension == "xcodeproj"
            } else {
                isSelfProjectReference = false
            }
            guard fileReference.location.path.hasSuffix(".xcodeproj") || isSelfProjectReference else {
                return
            }

            let resolved = try resolve(
                fileReference.location,
                groupBase: groupBase,
                containerBase: containerBase,
                rootURL: rootURL
            )
            guard resolved.pathExtension == "xcodeproj" else { return }
            let isPodsProject = Self.isPodsProject(resolved)
            isCocoaPodsGenerated = isCocoaPodsGenerated || isPodsProject

            var isDirectory: ObjCBool = false
            guard !isPodsProject,
                  FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return }

            projectPaths.insert(resolved.path)

        case .group(let group), .fileSystemSynchronizedGroup(let group):
            let nextGroupBase = try resolve(
                group.location,
                groupBase: groupBase,
                containerBase: containerBase,
                rootURL: rootURL
            )
            for child in group.children {
                try collectProjects(
                    from: child,
                    groupBase: nextGroupBase,
                    containerBase: containerBase,
                    rootURL: rootURL,
                    projectPaths: &projectPaths,
                    isCocoaPodsGenerated: &isCocoaPodsGenerated
                )
            }
        }
    }

    private func resolve(
        _ location: XCWorkspaceDataElementLocationType,
        groupBase: URL,
        containerBase: URL,
        rootURL: URL
    ) throws -> URL {
        let candidate: URL
        switch location {
        case .absolute(let path):
            guard path.hasPrefix("/") else {
                throw WorkspaceAnalyzerError.invalidAbsoluteLocation(location.description)
            }
            candidate = URL(fileURLWithPath: path)
        case .container(let path):
            candidate = containerBase.appendingPathComponent(path)
        case .group(let path):
            candidate = groupBase.appendingPathComponent(path)
        case .current(let path):
            candidate = containerBase.appendingPathComponent(path)
        case .developer:
            throw WorkspaceAnalyzerError.unsupportedLocationScheme(location.schema)
        case .other(let scheme, _):
            throw WorkspaceAnalyzerError.unsupportedLocationScheme(scheme)
        }

        let resolved = candidate.standardized.resolvingSymlinksInPath()
        guard Self.isContained(resolved.path, in: rootURL.path) else {
            throw WorkspaceAnalyzerError.projectReferenceOutsideRoot(
                reference: location.description,
                resolved: resolved.path,
                root: rootURL.path
            )
        }
        return resolved
    }

    private static func isContained(_ path: String, in rootPath: String) -> Bool {
        if rootPath == "/" { return path.hasPrefix("/") }
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func isPodsProject(_ url: URL) -> Bool {
        url.lastPathComponent == "Pods.xcodeproj" || url.pathComponents.contains("Pods")
    }
}
