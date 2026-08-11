// PkgLiftXcode/XcodeProjectEditor.swift
// Edits Xcode projects using XcodeProj.

import Foundation
import XcodeProj
import PathKit
import PkgLiftCore

/// Errors that can occur during Xcode project editing.
public enum XcodeProjectEditorError: Error, LocalizedError, Sendable {
    case projectNotFound(String)
    case invalidProject(String)
    case targetNotFound(String)
    case saveFailed(String)
    case packageReferenceNotFound(String)
    case packageRequirementConflict(String)
    case buildPhaseNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .projectNotFound(let path):
            return "Xcode project not found at path: \(path)"
        case .invalidProject(let path):
            return "Invalid or corrupted Xcode project at path: \(path)"
        case .targetNotFound(let name):
            return "Target not found: \(name)"
        case .saveFailed(let path):
            return "Failed to save Xcode project at path: \(path)"
        case .packageReferenceNotFound(let url):
            return "Swift package reference not found for repository: \(url)"
        case .packageRequirementConflict(let url):
            return "An existing Swift package reference for \(url) uses a different or unknown version requirement. PkgLift will not overwrite it automatically."
        case .buildPhaseNotFound(let name):
            return "Frameworks build phase not found for target: \(name)"
        }
    }
}

/// Editor for modifying an Xcode project to support SwiftPM migration.
public struct XcodeProjectEditor: Sendable {
    
    public init() {}
    
    /// Adds a SwiftPM package reference to the project.
    ///
    /// - Parameters:
    ///   - repositoryURL: The URL of the package repository.
    ///   - requirement: The version requirement for the package.
    ///   - projectPath: The path to the `.xcodeproj` file.
    /// - Throws: An error if the project cannot be opened, modified, or saved.
    public func addSwiftPMPackage(
        repositoryURL: String,
        requirement: SwiftPMVersionRequirement,
        to projectPath: String
    ) throws {
        let xcodeproj = try openProject(at: projectPath)
        let pbxproj = xcodeproj.pbxproj
        guard let project = pbxproj.rootObject else {
            throw XcodeProjectEditorError.invalidProject(projectPath)
        }

        let targetRepositoryURL = normalizeRepositoryURL(repositoryURL)

        if let existing = project.remotePackages.first(where: { hasSameRepository($0.repositoryURL, as: targetRepositoryURL) }) {
            guard swiftPMRequirement(from: existing.versionRequirement) == requirement else {
                throw XcodeProjectEditorError.packageRequirementConflict(repositoryURL)
            }
            return
        }
        
        // Convert SwiftPMVersionRequirement to XCRemoteSwiftPackageReference.VersionRequirement
        let versionReq: XCRemoteSwiftPackageReference.VersionRequirement
        switch requirement {
        case .from(let version):
            versionReq = .upToNextMajorVersion(version)
        case .upToNextMinor(let version):
            versionReq = .upToNextMinorVersion(version)
        case .exact(let version):
            versionReq = .exact(version)
        case .range(let from, let to):
            versionReq = .range(from: from, to: to)
        case .branch(let name):
            versionReq = .branch(name)
        case .revision(let rev):
            versionReq = .revision(rev)
        }

        let packageRef = XCRemoteSwiftPackageReference(
            repositoryURL: targetRepositoryURL,
            versionRequirement: versionReq
        )
        
        pbxproj.add(object: packageRef)
        project.remotePackages.append(packageRef)
        
        try saveProject(xcodeproj, at: projectPath)
    }
    
    /// Links a SwiftPM product to a specific target in the project.
    ///
    /// - Parameters:
    ///   - productName: The name of the SwiftPM product.
    ///   - targetName: The name of the native target to link against.
    ///   - repositoryURL: The URL of the package repository (used to find the package reference).
    ///   - projectPath: The path to the `.xcodeproj` file.
    /// - Throws: An error if the target, package, or build phases cannot be found or updated.
    public func linkSwiftPMProduct(
        productName: String,
        toTarget targetName: String,
        repositoryURL: String,
        in projectPath: String
    ) throws {
        let xcodeproj = try openProject(at: projectPath)
        let pbxproj = xcodeproj.pbxproj
        
        guard let target = pbxproj.nativeTargets.first(where: { $0.name == targetName }) else {
            throw XcodeProjectEditorError.targetNotFound(targetName)
        }
        
        // Find the remote package reference via the project's packages
        guard let project = try? pbxproj.rootProject() else {
            throw XcodeProjectEditorError.invalidProject("Cannot find root project")
        }

        let targetRepositoryURL = normalizeRepositoryURL(repositoryURL)
        guard let package = project.remotePackages.first(where: { hasSameRepository($0.repositoryURL, as: targetRepositoryURL) }) else {
            throw XcodeProjectEditorError.packageReferenceNotFound(repositoryURL)
        }

        let productDependency: XCSwiftPackageProductDependency
        if let existing = target.packageProductDependencies?.first(where: {
            $0.productName == productName && hasSameRepository($0.package?.repositoryURL, as: targetRepositoryURL)
        }) {
            productDependency = existing
        } else {
            let dependency = XCSwiftPackageProductDependency(
                productName: productName,
                package: package
            )
            pbxproj.add(object: dependency)

            if target.packageProductDependencies == nil {
                target.packageProductDependencies = []
            }
            target.packageProductDependencies?.append(dependency)
            productDependency = dependency
        }

        // Make sure the dependency is linked to target.
        if !(target.packageProductDependencies ?? []).contains(where: {
            $0.productName == productName && hasSameRepository($0.package?.repositoryURL, as: targetRepositoryURL)
        }) {
            target.packageProductDependencies?.append(productDependency)
        }

        // Add to the target's frameworks build phase.
        guard let phase = try target.frameworksBuildPhase() else {
            throw XcodeProjectEditorError.buildPhaseNotFound(targetName)
        }
        let buildFile = PBXBuildFile(product: productDependency)

        let alreadyLinked = phase.files?.contains {
            if let linkedProduct = $0.product {
                return linkedProduct.productName == productName
                    && hasSameRepository(linkedProduct.package?.repositoryURL, as: targetRepositoryURL)
            }
            if let file = $0.file {
                return file.name == productName
            }
            return false
        } == true

        if !alreadyLinked {
            pbxproj.add(object: buildFile)
            phase.files?.append(buildFile)
        }
        
        try saveProject(xcodeproj, at: projectPath)
    }
    
    // MARK: - Private Helpers
    
    private func openProject(at path: String) throws -> XcodeProj {
        let projectPath = Path(path)
        guard projectPath.exists else {
            throw XcodeProjectEditorError.projectNotFound(path)
        }
        
        do {
            return try XcodeProj(pathString: path)
        } catch {
            throw XcodeProjectEditorError.invalidProject(path)
        }
    }
    
    private func saveProject(_ xcodeproj: XcodeProj, at path: String) throws {
        do {
            try xcodeproj.write(pathString: path, override: true)
        } catch {
            throw XcodeProjectEditorError.saveFailed(path)
        }
    }

    private func normalizeRepositoryURL(_ repositoryURL: String) -> String {
        RepositoryIdentity.normalized(repositoryURL)
    }

    private func hasSameRepository(_ lhs: String?, as rhs: String) -> Bool {
        guard let lhs = lhs else { return false }
        return RepositoryIdentity.matches(lhs, rhs)
    }

    private func swiftPMRequirement(
        from requirement: XCRemoteSwiftPackageReference.VersionRequirement?
    ) -> SwiftPMVersionRequirement? {
        guard let requirement else { return nil }
        switch requirement {
        case .upToNextMajorVersion(let version): return .from(version)
        case .upToNextMinorVersion(let version): return .upToNextMinor(version)
        case .exact(let version): return .exact(version)
        case .range(let from, let to): return .range(from: from, to: to)
        case .branch(let name): return .branch(name)
        case .revision(let revision): return .revision(revision)
        }
    }
}
