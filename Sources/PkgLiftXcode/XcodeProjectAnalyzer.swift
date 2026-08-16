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
        var hasCocoaPodsIntegration = false

        guard let pbxProject = try xcodeproj.pbxproj.rootProject() else {
            throw XcodeProjectAnalyzerError.invalidProject(path)
        }
        
        let nativeTargets = xcodeproj.pbxproj.nativeTargets
        
        for target in nativeTargets {
            // Extract target info
            let targetName = target.name
            let targetType = target.productType?.rawValue ?? "unknown"
            
            let environment = effectiveEnvironment(
                for: target,
                project: pbxProject,
                projectPath: projectPath
            )
            
            let targetInfo = TargetInfo(
                name: targetName,
                type: targetType,
                platform: environment?.platform,
                deploymentTarget: environment?.deploymentTarget,
                sourceProfile: sourceProfile(for: target)
            )
            targetInfos.append(targetInfo)
            
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

        // XcodeProj exposes PBX objects through dictionary-backed collections,
        // whose iteration order is not a stable serialization contract. Keep
        // project analysis JSON deterministic across otherwise identical runs.
        targetInfos.sort {
            if $0.name != $1.name { return $0.name < $1.name }
            if $0.type != $1.type { return $0.type < $1.type }
            if $0.platform != $1.platform { return ($0.platform ?? "") < ($1.platform ?? "") }
            if $0.deploymentTarget != $1.deploymentTarget {
                return ($0.deploymentTarget ?? "") < ($1.deploymentTarget ?? "")
            }
            return sourceProfileSortKey($0.sourceProfile)
                .lexicographicallyPrecedes(sourceProfileSortKey($1.sourceProfile))
        }
        
        let projectInfo = ProjectInfo(
            projectPath: path,
            workspacePath: nil,
            targets: targetInfos
        )
        
        // Detect existing SwiftPM package references via PBXProject.packages
        var swiftPMPackages: [SwiftPMDependency] = []
        
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
            packageLinkedProducts.sort {
                if $0.targetName != $1.targetName {
                    return $0.targetName < $1.targetName
                }
                return $0.productName < $1.productName
            }
            
            let swiftPMDependency = SwiftPMDependency(
                repositoryURL: repositoryURL,
                requirement: requirement,
                linkedProducts: packageLinkedProducts
            )
            swiftPMPackages.append(swiftPMDependency)
        }
        swiftPMPackages.sort {
            let lhsIdentity = RepositoryIdentity.normalized($0.repositoryURL)
            let rhsIdentity = RepositoryIdentity.normalized($1.repositoryURL)
            if lhsIdentity != rhsIdentity { return lhsIdentity < rhsIdentity }
            if $0.repositoryURL != $1.repositoryURL {
                return $0.repositoryURL < $1.repositoryURL
            }

            let lhsRequirement = requirementSortKey($0.requirement)
            let rhsRequirement = requirementSortKey($1.requirement)
            if lhsRequirement != rhsRequirement {
                return lhsRequirement.lexicographicallyPrecedes(rhsRequirement)
            }

            let lhsProducts = linkedProductSortKey($0.linkedProducts)
            let rhsProducts = linkedProductSortKey($1.linkedProducts)
            return lhsProducts.lexicographicallyPrecedes(rhsProducts)
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

    /// Builds a conservative profile without opening or reading source files.
    ///
    /// A synchronized root can implicitly contribute sources that are absent
    /// from the traditional sources build phase, so its presence makes the
    /// PBX-only profile incomplete.
    private func sourceProfile(for target: PBXNativeTarget) -> TargetSourceProfile {
        var languages: [SourceLanguage] = []
        var completeness: SourceProfileCompleteness = .complete

        if target.fileSystemSynchronizedGroups?.isEmpty == false {
            completeness = .incomplete
        }

        do {
            guard let sourcesBuildPhase = try target.sourcesBuildPhase() else {
                return TargetSourceProfile(
                    languages: languages,
                    completeness: completeness
                )
            }

            for buildFile in sourcesBuildPhase.files ?? [] {
                guard let fileReference = buildFile.file as? PBXFileReference,
                      let fileType = fileReference.explicitFileType ?? fileReference.lastKnownFileType,
                      let language = Self.sourceLanguage(forPBXFileType: fileType) else {
                    completeness = .incomplete
                    continue
                }
                languages.append(language)
            }
        } catch {
            completeness = .incomplete
        }

        return TargetSourceProfile(
            languages: languages,
            completeness: completeness
        )
    }

    private static func sourceLanguage(forPBXFileType fileType: String) -> SourceLanguage? {
        switch fileType {
        case "sourcecode.swift": .swift
        case "sourcecode.c.objc": .objectiveC
        case "sourcecode.cpp.objcpp": .objectiveCPlusPlus
        case "sourcecode.c.c": .c
        case "sourcecode.cpp.cpp": .cPlusPlus
        default: nil
        }
    }

    private func sourceProfileSortKey(_ profile: TargetSourceProfile?) -> [String] {
        guard let profile else { return [""] }
        return [profile.completeness.rawValue] + profile.languages.map(\.rawValue)
    }

    /// Resolves the platform settings that Xcode applies to every target configuration.
    ///
    /// Xcode applies project configuration settings before target configuration settings.
    /// Each configuration may in turn be backed by an xcconfig. We only report an
    /// environment when every target configuration produces the same concrete result;
    /// returning `nil` is safer than selecting an arbitrary Debug or Release value.
    private func effectiveEnvironment(
        for target: PBXNativeTarget,
        project: PBXProject,
        projectPath: Path
    ) -> TargetEnvironment? {
        guard let targetConfigurations = target.buildConfigurationList?.buildConfigurations,
              !targetConfigurations.isEmpty else {
            return nil
        }

        let projectConfigurations = project.buildConfigurationList?.buildConfigurations ?? []
        var environments = Set<TargetEnvironment>()

        for targetConfiguration in targetConfigurations {
            let matchingProjectConfigurations = projectConfigurations.filter {
                $0.name == targetConfiguration.name
            }

            guard matchingProjectConfigurations.count == 1 else {
                // Xcode normally pairs target and project configurations by name.
                // A missing or duplicate pair leaves the effective setting unknown.
                return nil
            }
            let projectConfiguration = matchingProjectConfigurations[0]

            guard let environment = resolveEnvironment(
                targetConfiguration: targetConfiguration,
                projectConfiguration: projectConfiguration,
                projectPath: projectPath
            ) else {
                return nil
            }
            environments.insert(environment)
        }

        guard environments.count == 1 else { return nil }
        return environments.first
    }

    private func resolveEnvironment(
        targetConfiguration: XCBuildConfiguration,
        projectConfiguration: XCBuildConfiguration?,
        projectPath: Path
    ) -> TargetEnvironment? {
        let projectBaseSettings = projectConfiguration.map {
            baseConfigurationSettings(for: $0, projectPath: projectPath)
        } ?? .known([:])
        let projectSettings = projectConfiguration.map(\.buildSettings) ?? [:]
        let targetBaseSettings = baseConfigurationSettings(
            for: targetConfiguration,
            projectPath: projectPath
        )

        let layers: [BuildSettingsLayer] = [
            projectBaseSettings,
            .known(projectSettings),
            targetBaseSettings,
            .known(targetConfiguration.buildSettings),
        ]

        var resolvedPlatforms = Set<String>()
        var deploymentTarget: String?

        for (setting, platform) in Self.deploymentTargetSettings {
            switch resolve(setting: setting, from: layers) {
            case .missing:
                continue
            case .unresolved:
                return nil
            case .value(let value):
                resolvedPlatforms.insert(platform)
                deploymentTarget = value
            }
        }

        switch resolve(setting: "SDKROOT", from: layers) {
        case .missing:
            break
        case .unresolved:
            return nil
        case .value(let sdkRoot):
            if sdkRoot.caseInsensitiveCompare("auto") == .orderedSame {
                break
            }
            guard let platform = platform(forSDKRoot: sdkRoot) else { return nil }
            resolvedPlatforms.insert(platform)
        }

        guard resolvedPlatforms.count == 1, let platform = resolvedPlatforms.first else {
            return nil
        }

        return TargetEnvironment(platform: platform, deploymentTarget: deploymentTarget)
    }

    private func baseConfigurationSettings(
        for configuration: XCBuildConfiguration,
        projectPath: Path
    ) -> BuildSettingsLayer {
        let configurationPath: Path?

        do {
            if let baseConfiguration = configuration.baseConfiguration {
                configurationPath = try baseConfiguration.fullPath(sourceRoot: projectPath.parent())
            } else if let anchor = configuration.baseConfigurationAnchor,
                      let relativePath = configuration.baseConfigurationReferenceRelativePath,
                      let anchorPath = try anchor.fullPath(sourceRoot: projectPath.parent()) {
                configurationPath = anchorPath + Path(relativePath)
            } else {
                return .known([:])
            }
        } catch {
            return .unavailable
        }

        guard let configurationPath else { return .unavailable }

        do {
            var activeIncludes = Set<String>()
            let settings = try relevantXCConfigSettings(
                at: configurationPath,
                activeIncludes: &activeIncludes
            )
            return .known(settings)
        } catch {
            // An unreadable or unsupported xcconfig might contain a relevant
            // higher-precedence setting. Preserve safety by refusing to infer.
            return .unavailable
        }
    }

    /// Parses only the platform settings needed by PkgLift. Xcode resolves all
    /// includes before interpreting a file's own settings, so local assignments
    /// always override included assignments regardless of their textual position.
    /// Unsupported constructs that could affect these settings fail closed.
    private func relevantXCConfigSettings(
        at path: Path,
        activeIncludes: inout Set<String>
    ) throws -> BuildSettings {
        let canonicalURL = URL(fileURLWithPath: path.string)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let canonicalPath = canonicalURL.path

        guard FileManager.default.fileExists(atPath: canonicalPath) else {
            throw XCConfigResolutionError.missingRequiredInclude
        }
        guard activeIncludes.insert(canonicalPath).inserted else {
            throw XCConfigResolutionError.includeCycle
        }
        defer { activeIncludes.remove(canonicalPath) }

        let contents: String
        do {
            contents = try String(contentsOf: canonicalURL, encoding: .utf8)
        } catch {
            throw XCConfigResolutionError.unreadable
        }

        var includeDirectives: [XCConfigIncludeDirective] = []
        var localSettings: BuildSettings = [:]
        var continuingUnrelatedSetting = false

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = removingLineComment(from: rawLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if continuingUnrelatedSetting {
                continuingUnrelatedSetting = line.hasSuffix("\\")
                continue
            }
            guard !line.isEmpty else { continue }

            if line.hasSuffix("\\") {
                if line.hasPrefix("#include") || relevantSettingPrefix(in: line) != nil {
                    throw XCConfigResolutionError.unsupportedRelevantSyntax
                }
                continuingUnrelatedSetting = true
                continue
            }

            if line.hasPrefix("#include") {
                includeDirectives.append(try parseIncludeDirective(line))
                continue
            }

            if line.hasPrefix("#") {
                throw XCConfigResolutionError.unsupportedDirective
            }

            guard let settingName = relevantSettingPrefix(in: line) else { continue }
            guard !line.contains("/*"), !line.contains("*/") else {
                throw XCConfigResolutionError.unsupportedRelevantSyntax
            }
            guard let equalsIndex = line.firstIndex(of: "=") else {
                throw XCConfigResolutionError.unsupportedRelevantSyntax
            }

            let leftHandSide = line[..<equalsIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard leftHandSide == settingName else {
                // Conditional selectors and operators such as += or ?= require
                // Xcode's full evaluation environment, so they remain unknown.
                throw XCConfigResolutionError.unsupportedRelevantSyntax
            }

            var value = line[line.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasSuffix(";") {
                value.removeLast()
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !value.isEmpty else {
                throw XCConfigResolutionError.unsupportedRelevantSyntax
            }
            localSettings[settingName] = .string(value)
        }

        var settings: BuildSettings = [:]
        let includingDirectory = Path(canonicalPath).parent()
        for directive in includeDirectives {
            if let includePath = resolveIncludePath(
                directive.path,
                relativeTo: includingDirectory
            ) {
                let included = try relevantXCConfigSettings(
                    at: includePath,
                    activeIncludes: &activeIncludes
                )
                settings.merge(included, uniquingKeysWith: { _, included in included })
            } else if !directive.optional {
                throw XCConfigResolutionError.missingRequiredInclude
            }
        }
        settings.merge(localSettings, uniquingKeysWith: { _, local in local })
        return settings
    }

    private func parseIncludeDirective(_ line: String) throws -> XCConfigIncludeDirective {
        let optional: Bool
        let keyword: String
        if line.hasPrefix("#include?") {
            optional = true
            keyword = "#include?"
        } else {
            optional = false
            keyword = "#include"
        }

        let remainder = line.dropFirst(keyword.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard remainder.first == "\"" else {
            throw XCConfigResolutionError.unsupportedDirective
        }

        let pathStart = remainder.index(after: remainder.startIndex)
        guard let pathEnd = remainder[pathStart...].firstIndex(of: "\"") else {
            throw XCConfigResolutionError.unsupportedDirective
        }
        let includePath = String(remainder[pathStart..<pathEnd])
        let trailing = remainder[remainder.index(after: pathEnd)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !includePath.isEmpty,
              trailing.isEmpty,
              !includePath.contains("$("),
              !includePath.contains("${") else {
            throw XCConfigResolutionError.unsupportedDirective
        }

        return XCConfigIncludeDirective(path: includePath, optional: optional)
    }

    private func resolveIncludePath(
        _ includePath: String,
        relativeTo includingDirectory: Path
    ) -> Path? {
        let rawPath = Path(includePath)
        let resolvedPath = rawPath.isAbsolute ? rawPath : includingDirectory + rawPath
        return resolvedPath.exists ? resolvedPath : nil
    }

    private func relevantSettingPrefix(in line: String) -> String? {
        for settingName in Self.relevantEnvironmentSettings where line.hasPrefix(settingName) {
            let remainder = line.dropFirst(settingName.count)
            guard let first = remainder.first else { return settingName }
            if first.isWhitespace || first == "=" || first == "[" || first == "+" || first == "?" {
                return settingName
            }
        }
        return nil
    }

    private func removingLineComment(from line: String) -> String {
        guard let comment = line.range(of: "//") else { return line }
        return String(line[..<comment.lowerBound])
    }

    private func resolve(setting name: String, from layers: [BuildSettingsLayer]) -> SettingResolution {
        for layer in layers.reversed() {
            switch layer {
            case .unavailable:
                return .unresolved
            case .known(let settings):
                if settings.keys.contains(where: { isVariant($0, of: name) }) {
                    return .unresolved
                }
                guard let setting = settings[name] else { continue }
                guard case .string(let rawValue) = setting else { return .unresolved }

                let value = normalizedSettingValue(rawValue)
                if value == "$(inherited)" { continue }
                if value.isEmpty || value.contains("$(") || value.contains("${")
                    || value.contains("/*") || value.contains("*/") {
                    return .unresolved
                }
                return .value(value)
            }
        }

        return .missing
    }

    private func isVariant(_ candidate: String, of settingName: String) -> Bool {
        guard candidate != settingName, candidate.hasPrefix(settingName) else {
            return false
        }
        let remainder = candidate.dropFirst(settingName.count)
        guard let first = remainder.first else { return false }
        return !first.isLetter && !first.isNumber && first != "_"
    }

    private func requirementSortKey(_ requirement: SwiftPMVersionRequirement?) -> [String] {
        guard let requirement else { return ["0"] }
        return switch requirement {
        case .from(let version): ["1", version]
        case .upToNextMinor(let version): ["2", version]
        case .exact(let version): ["3", version]
        case .range(let from, let to): ["4", from, to]
        case .branch(let name): ["5", name]
        case .revision(let revision): ["6", revision]
        }
    }

    private func linkedProductSortKey(_ products: [LinkedProduct]) -> [String] {
        products.flatMap { [$0.targetName, $0.productName] }
    }

    private func normalizedSettingValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.first == "\"", trimmed.last == "\"" else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private func platform(forSDKRoot sdkRoot: String) -> String? {
        let normalizedSDKRoot = sdkRoot.lowercased()
        let platforms: [([String], String)] = [
            (["iphoneos", "iphonesimulator"], "iOS"),
            (["macosx"], "macOS"),
            (["appletvos", "appletvsimulator"], "tvOS"),
            (["watchos", "watchsimulator"], "watchOS"),
            (["xros", "xrsimulator"], "visionOS"),
        ]
        for (sdkPrefixes, platform) in platforms
            where sdkPrefixes.contains(where: { matchesSDKIdentifier(normalizedSDKRoot, prefix: $0) }) {
            return platform
        }
        return nil
    }

    private func matchesSDKIdentifier(_ identifier: String, prefix: String) -> Bool {
        guard identifier.hasPrefix(prefix) else { return false }
        let suffix = identifier.dropFirst(prefix.count)
        guard !suffix.isEmpty else { return true }
        return suffix
            .split(separator: ".", omittingEmptySubsequences: false)
            .allSatisfy { component in
                !component.isEmpty && component.allSatisfy(\.isNumber)
            }
    }
}

private extension XcodeProjectAnalyzer {
    struct TargetEnvironment: Hashable {
        let platform: String
        let deploymentTarget: String?
    }

    enum BuildSettingsLayer {
        case known(BuildSettings)
        case unavailable
    }

    enum SettingResolution {
        case missing
        case unresolved
        case value(String)
    }

    struct XCConfigIncludeDirective {
        let path: String
        let optional: Bool
    }

    enum XCConfigResolutionError: Error {
        case includeCycle
        case missingRequiredInclude
        case unreadable
        case unsupportedDirective
        case unsupportedRelevantSyntax
    }

    static let deploymentTargetSettings: [(String, String)] = [
        ("IPHONEOS_DEPLOYMENT_TARGET", "iOS"),
        ("MACOSX_DEPLOYMENT_TARGET", "macOS"),
        ("TVOS_DEPLOYMENT_TARGET", "tvOS"),
        ("WATCHOS_DEPLOYMENT_TARGET", "watchOS"),
        ("XROS_DEPLOYMENT_TARGET", "visionOS"),
    ]

    static let relevantEnvironmentSettings = Set(
        deploymentTargetSettings.map(\.0) + ["SDKROOT"]
    )
}
