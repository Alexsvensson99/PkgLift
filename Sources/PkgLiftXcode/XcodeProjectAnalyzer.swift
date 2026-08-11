// PkgLiftXcode/XcodeProjectAnalyzer.swift
// Analyzes Xcode projects using XcodeProj.

import Foundation
import XcodeProj
import PathKit
import PkgLiftCore

/// Result of an Xcode project analysis.
public struct XcodeAnalysisResult: Sendable {
    public let projectInfo: ProjectInfo
    public let swiftPMState: SwiftPMState
    public let targets: [TargetInfo]
    public let hasCocoaPodsIntegration: Bool
    
    public init(projectInfo: ProjectInfo, swiftPMState: SwiftPMState, targets: [TargetInfo], hasCocoaPodsIntegration: Bool) {
        self.projectInfo = projectInfo
        self.swiftPMState = swiftPMState
        self.targets = targets
        self.hasCocoaPodsIntegration = hasCocoaPodsIntegration
    }
}

/// Errors that can occur during Xcode project analysis.
public enum XcodeProjectAnalyzerError: Error, LocalizedError, Sendable {
    case projectNotFound(String)
    case invalidProject(String)
    
    public var errorDescription: String? {
        switch self {
        case .projectNotFound(let path):
            return "Xcode project not found at path: \(path)"
        case .invalidProject(let path):
            return "Invalid or corrupted Xcode project at path: \(path)"
        }
    }
}

/// Main analyzer for Xcode projects.
public struct XcodeProjectAnalyzer: Sendable {
    
    public init() {}
    
    /// Analyzes an Xcode project at the given path.
    ///
    /// - Parameter path: The absolute path to the `.xcodeproj` file.
    /// - Returns: An `XcodeAnalysisResult` containing the project information and SwiftPM state.
    /// - Throws: An error if the project cannot be opened or parsed.
    public func analyzeProject(at path: String) throws -> XcodeAnalysisResult {
        let projectPath = Path(path)
        guard projectPath.exists else {
            throw XcodeProjectAnalyzerError.projectNotFound(path)
        }
        
        let xcodeproj: XcodeProj
        do {
            xcodeproj = try XcodeProj(pathString: path)
        } catch {
            throw XcodeProjectAnalyzerError.invalidProject(path)
        }
        
        var targetInfos: [TargetInfo] = []
        var linkedProducts: [LinkedProduct] = []
        var hasCocoaPodsIntegration = false
        
        let nativeTargets = xcodeproj.pbxproj.nativeTargets
        
        for target in nativeTargets {
            // Extract target info
            let targetName = target.name
            let targetType = target.productType?.rawValue ?? "unknown"
            
            // Try to find deployment target from build configurations
            var deploymentTarget: String? = nil
            var platform: String? = nil
            
            if let buildConfigurationList = target.buildConfigurationList {
                for config in buildConfigurationList.buildConfigurations {
                    let buildSettings = config.buildSettings
                    if let iphonesos = buildSettings["IPHONEOS_DEPLOYMENT_TARGET"] {
                        deploymentTarget = "\(iphonesos)"
                        platform = "iOS"
                    } else if let macosx = buildSettings["MACOSX_DEPLOYMENT_TARGET"] {
                        deploymentTarget = "\(macosx)"
                        platform = "macOS"
                    } else if let tvos = buildSettings["TVOS_DEPLOYMENT_TARGET"] {
                        deploymentTarget = "\(tvos)"
                        platform = "tvOS"
                    } else if let watchos = buildSettings["WATCHOS_DEPLOYMENT_TARGET"] {
                        deploymentTarget = "\(watchos)"
                        platform = "watchOS"
                    }
                    
                    if deploymentTarget != nil {
                        break
                    }
                }
            }
            
            let targetInfo = TargetInfo(
                name: targetName,
                type: targetType,
                platform: platform,
                deploymentTarget: deploymentTarget
            )
            targetInfos.append(targetInfo)
            
            // Detect SwiftPM products linked to targets
            if let dependencies = target.packageProductDependencies {
                for dependency in dependencies {
                    let productName = dependency.productName
                    let linkedProduct = LinkedProduct(productName: productName, targetName: targetName)
                    linkedProducts.append(linkedProduct)
                }
            }
            
            // Detect CocoaPods integration
            // Looks for [CP] build phases — note: name() is a function, not a property
            let buildPhases = target.buildPhases
            for phase in buildPhases {
                if let phaseName = phase.name(), phaseName.hasPrefix("[CP]") {
                    hasCocoaPodsIntegration = true
                }
            }
            
            // Looks for Pods framework references
            if let frameworksBuildPhase = try target.frameworksBuildPhase() {
                if let files = frameworksBuildPhase.files {
                    for file in files {
                        if let fileRef = file.file {
                            if let name = fileRef.name, name.hasPrefix("Pods_") {
                                hasCocoaPodsIntegration = true
                            }
                        }
                    }
                }
            }
        }
        
        let projectInfo = ProjectInfo(
            projectPath: path,
            workspacePath: nil,
            targets: targetInfos
        )
        
        // Detect existing SwiftPM package references via PBXProject.packages
        var swiftPMPackages: [SwiftPMDependency] = []
        
        guard let pbxProject = try xcodeproj.pbxproj.rootProject() else {
            throw XcodeProjectAnalyzerError.invalidProject(path)
        }
        
        let remotePackages = pbxProject.remotePackages
        
        for package in remotePackages {
            guard let repositoryURL = package.repositoryURL else { continue }
            
            var requirement: SwiftPMVersionRequirement? = nil
            if let versionReq = package.versionRequirement {
                switch versionReq {
                case .upToNextMajorVersion(let version):
                    requirement = .from(version)
                case .upToNextMinorVersion(let version):
                    requirement = .upToNextMinor(version)
                case .exact(let version):
                    requirement = .exact(version)
                case .branch(let branchName):
                    requirement = .branch(branchName)
                case .revision(let rev):
                    requirement = .revision(rev)
                case .range(let from, let to):
                    requirement = .range(from: from, to: to)
                }
            }
            
            // Find linked products for this package
            var packageLinkedProducts: [LinkedProduct] = []
            for target in nativeTargets {
                if let dependencies = target.packageProductDependencies {
                    for dependency in dependencies {
                        if dependency.package == package {
                            packageLinkedProducts.append(LinkedProduct(productName: dependency.productName, targetName: target.name))
                        }
                    }
                }
            }
            
            let swiftPMDependency = SwiftPMDependency(
                repositoryURL: repositoryURL,
                requirement: requirement,
                linkedProducts: packageLinkedProducts
            )
            swiftPMPackages.append(swiftPMDependency)
        }
        
        let parentPath = Path(path).parent()
        let packageResolvedPath = parentPath + Path("project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let hasPackageResolved = packageResolvedPath.exists
        
        let swiftPMState = SwiftPMState(
            packages: swiftPMPackages,
            hasPackageResolved: hasPackageResolved
        )
        
        return XcodeAnalysisResult(
            projectInfo: projectInfo,
            swiftPMState: swiftPMState,
            targets: targetInfos,
            hasCocoaPodsIntegration: hasCocoaPodsIntegration
        )
    }
}
