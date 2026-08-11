// PkgLiftXcode/WorkspaceAnalyzer.swift
// Analyzes Xcode workspaces using XcodeProj.

import Foundation
import XcodeProj
import PathKit
import PkgLiftCore

/// Errors that can occur during Xcode workspace analysis.
public enum WorkspaceAnalyzerError: Error, LocalizedError, Sendable {
    case workspaceNotFound(String)
    case invalidWorkspace(String)
    
    public var errorDescription: String? {
        switch self {
        case .workspaceNotFound(let path):
            return "Xcode workspace not found at path: \(path)"
        case .invalidWorkspace(let path):
            return "Invalid or corrupted Xcode workspace at path: \(path)"
        }
    }
}

/// Result of a workspace analysis.
public struct WorkspaceAnalysisResult: Sendable {
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
    /// - Parameter path: The absolute path to the `.xcworkspace` file.
    /// - Returns: A `WorkspaceAnalysisResult` containing project paths and whether the workspace is CocoaPods-generated.
    /// - Throws: An error if the workspace cannot be opened or parsed.
    public func analyzeWorkspace(at path: String) throws -> WorkspaceAnalysisResult {
        let workspacePath = Path(path)
        guard workspacePath.exists else {
            throw WorkspaceAnalyzerError.workspaceNotFound(path)
        }
        
        let workspace: XCWorkspace
        do {
            workspace = try XCWorkspace(pathString: path)
        } catch {
            throw WorkspaceAnalyzerError.invalidWorkspace(path)
        }
        
        var projectPaths: [String] = []
        var isCocoaPodsGenerated = false
        
        // Traverse workspace data to find projects
        for element in workspace.data.children {
            switch element {
            case .file(let fileRef):
                let location = fileRef.location
                // Usually group/relative, so we extract the path
                if location.path.hasSuffix(".xcodeproj") {
                    projectPaths.append(location.path)
                }
                
                // CocoaPods generated workspaces usually have a Pods/Pods.xcodeproj reference
                if location.path.contains("Pods.xcodeproj") || location.path.hasSuffix("Pods.xcodeproj") {
                    isCocoaPodsGenerated = true
                }
            case .group(let group):
                // Recursively traverse groups
                isCocoaPodsGenerated = checkGroupForCocoaPods(group, projectPaths: &projectPaths) || isCocoaPodsGenerated
            case .fileSystemSynchronizedGroup(let group):
                isCocoaPodsGenerated = checkGroupForCocoaPods(group, projectPaths: &projectPaths) || isCocoaPodsGenerated
            }
        }
        
        return WorkspaceAnalysisResult(
            projectPaths: projectPaths,
            isCocoaPodsGenerated: isCocoaPodsGenerated
        )
    }
    
    private func checkGroupForCocoaPods(_ group: XCWorkspaceDataGroup, projectPaths: inout [String]) -> Bool {
        var isCocoaPods = false
        for element in group.children {
            switch element {
            case .file(let fileRef):
                if fileRef.location.path.hasSuffix(".xcodeproj") {
                    projectPaths.append(fileRef.location.path)
                }
                if fileRef.location.path.contains("Pods.xcodeproj") {
                    isCocoaPods = true
                }
            case .group(let subGroup):
                if checkGroupForCocoaPods(subGroup, projectPaths: &projectPaths) {
                    isCocoaPods = true
                }
            case .fileSystemSynchronizedGroup(let subGroup):
                if checkGroupForCocoaPods(subGroup, projectPaths: &projectPaths) {
                    isCocoaPods = true
                }
            }
        }
        return isCocoaPods
    }
}
