//
//  CommandContext.swift
//  PkgLiftCLI
//

import Foundation
import PkgLiftCore
import PkgLiftCocoaPods
import PkgLiftMigration
import PkgLiftRegistry
import PkgLiftXcode

// MARK: - CLI-level snapshot

struct CommandContext: Sendable {
    let discovery: DiscoveredFiles
    let configuration: PkgLiftConfiguration
    let podfileFeatures: PodfileFeatures
    let podfileContent: String?
    let directDependencies: [CocoaPodDependency]
    let mappedDependencies: [CocoaPodDependency]
    let registryMappings: [String: RegistryMapping]
    let resolvedProjectPath: String?
    let resolvedWorkspacePath: String?
    let isWorkspaceSelected: Bool
    let xcodeAnalysis: XcodeAnalysisResult?

    var planURL: URL {
        URL(fileURLWithPath: discovery.rootPath)
            .appendingPathComponent(".pkglift")
            .appendingPathComponent("plan.json")
    }

    var transitiveDependencies: [CocoaPodDependency] {
        mappedDependencies.filter { !$0.isDirect }
    }

    var projectPath: String {
        resolvedProjectPath ?? discovery.rootPath
    }

    func mappedDependency(for name: String) -> CocoaPodDependency? {
        mappedDependencies.first(where: { $0.name == name })
    }

    func migrationCandidates(includeTransitive: Bool = false) -> [PkgLiftCore.MigrationCandidate] {
        let classifier = MigrationClassifier()
        let versionMapper = VersionMapper()

        let dependencies = includeTransitive ? mappedDependencies : directDependencies

        let candidates = dependencies.map { dependency -> PkgLiftCore.MigrationCandidate in
            let mapping = registryMappings[dependency.name]

            let isAlreadyMigrated: Bool = {
                guard let mapping = mapping else { return false }
                guard let packages = xcodeAnalysis?.swiftPMState.packages else { return false }

                return packages.contains {
                    $0.repositoryURL.caseInsensitiveCompare(mapping.swiftpm.repository) == .orderedSame
                }
            }()

            let matchingTargetCount: Int = {
                guard dependency.targets.count == 1,
                      let targetName = dependency.targets.first,
                      let targets = xcodeAnalysis?.projectInfo.targets else { return 0 }
                return targets.filter { $0.name == targetName }.count
            }()

            var result = classifier.classify(
                dependency: dependency,
                mapping: mapping,
                isAlreadyMigrated: isAlreadyMigrated,
                isTargetMappingKnown: matchingTargetCount == 1,
                podfileFeatures: podfileFeatures
            )

            let denied = configuration.migration?.deny ?? []
            let allowed = configuration.migration?.allow
            if denied.contains(dependency.name) || denied.contains(dependency.baseName) {
                result = MigrationClassification(
                    category: .blocked,
                    reason: "Dependency is denied by .pkglift.yml"
                )
            } else if let allowed,
                      !allowed.contains(dependency.name),
                      !allowed.contains(dependency.baseName) {
                result = MigrationClassification(
                    category: .review,
                    reason: "Dependency is not in the .pkglift.yml migration allow list"
                )
            }

            var coreClassification: PkgLiftCore.MigrationClassification
            switch result.category {
            case .auto:
                coreClassification = .auto
            case .review:
                coreClassification = .review
            case .blocked:
                coreClassification = .blocked
            case .unknown:
                coreClassification = .unknown
            }

            var issues: [MigrationIssue]
            if result.category == .auto {
                issues = []
            } else {
                let severity: MigrationIssue.Severity = result.category == .blocked ? .error : .warning
                var details: [String] = [result.reason]
                if dependency.source != .registry {
                    details.append("Dependency source is not CocoaPods registry")
                }

                issues = [
                    MigrationIssue(
                        severity: severity,
                        message: details[0],
                        detail: details.count > 1 ? details.dropFirst().joined(separator: ". ") : nil,
                        dependency: dependency.name
                    )
                ]
            }

            let mappedPackage: PkgLiftCore.PackageCandidate?
            if let mapping {
                let versionRequirement: SwiftPMVersionRequirement?
                if let mapped = versionMapper.map(constraint: dependency.version ?? "", resolvedVersion: dependency.version) {
                    versionRequirement = switch mapped {
                    case .exact(let v): .exact(v)
                    case .from(let v): .from(v)
                    case .upToNextMinor(let v): .upToNextMinor(v)
                    }
                } else {
                    versionRequirement = nil
                }

                mappedPackage = PkgLiftCore.PackageCandidate(
                    repositoryURL: mapping.swiftpm.repository,
                    products: mapping.swiftpm.products,
                    versionRequirement: versionRequirement,
                    confidence: mapping.migration.confidence
                )
            } else {
                mappedPackage = nil
            }

            if coreClassification == .auto,
               (mappedPackage?.versionRequirement == nil ||
                mappedPackage?.products.isEmpty != false ||
                dependency.targets.count != 1 ||
                matchingTargetCount != 1) {
                coreClassification = .review
                issues.append(MigrationIssue(
                    severity: .warning,
                    message: "Automatic migration data is incomplete or ambiguous",
                    detail: "PkgLift requires an explicit version, package product, and exactly one existing Xcode target. It deliberately refused to invent missing values.",
                    dependency: dependency.name
                ))
            }

            if coreClassification == .auto,
               let mappedPackage,
               let existingPackage = existingPackage(
                    matching: mappedPackage.repositoryURL,
                    in: xcodeAnalysis?.swiftPMState.packages ?? []
               ),
               existingPackage.requirement != mappedPackage.versionRequirement {
                coreClassification = .review
                issues.append(MigrationIssue(
                    severity: .warning,
                    message: "Existing SwiftPM package uses a different or unknown version requirement",
                    detail: "PkgLift will not silently replace or reinterpret the existing package requirement.",
                    dependency: dependency.name
                ))
            }

            return PkgLiftCore.MigrationCandidate(
                pod: dependency,
                classification: coreClassification,
                packageCandidate: mappedPackage,
                reasons: [result.reason],
                issues: issues
            )
        }

        return candidates
    }

    func migrationReadinessScore() -> Int {
        let candidates = migrationCandidates(includeTransitive: false)
        let readiness = ReadinessScorer()

        return readiness.score(
            autoCount: candidates.filter { $0.classification == .auto }.count,
            totalDirectCount: directDependencies.count,
            blockedDirectCount: candidates.filter { $0.classification == .blocked }.count,
            hasPostInstallHook: podfileFeatures.hasPostInstallHook,
            hasPreInstallHook: podfileFeatures.hasPreInstallHook,
            hasScriptPhase: podfileFeatures.hasScriptPhase,
            hasDynamicRuby: podfileFeatures.hasDynamicRuby,
            noProjectRisks: !podfileFeatures.hasDynamicRuby &&
                !podfileFeatures.hasPostInstallHook &&
                !podfileFeatures.hasPreInstallHook &&
                !podfileFeatures.hasScriptPhase
        )
    }

    func buildMigrationPlan() -> PkgLiftCore.MigrationPlan {
        let candidates = migrationCandidates()

        let entries: [PkgLiftCore.MigrationPlanEntry] = candidates.map { candidate in
            var actions: [PkgLiftCore.MigrationAction] = []

            if let packageCandidate = candidate.packageCandidate,
               let requirement = packageCandidate.versionRequirement,
               let targetName = candidate.pod.targets.count == 1 ? candidate.pod.targets[0] : nil,
               candidate.classification == .auto {
                actions.append(.removePod(name: candidate.pod.name))
                actions.append(.addSwiftPackage(
                    repositoryURL: packageCandidate.repositoryURL,
                    requirement: requirement
                ))

                for product in packageCandidate.products {
                    actions.append(
                        .linkProduct(
                            repositoryURL: packageCandidate.repositoryURL,
                            productName: product,
                            targetName: targetName
                        )
                    )
                }
            } else {
                actions.append(
                    .manual(
                        description: "No compatible package candidate available for automatic migration."
                    )
                )
            }

            return PkgLiftCore.MigrationPlanEntry(
                podName: candidate.pod.name,
                currentVersion: candidate.pod.version,
                classification: candidate.classification,
                actions: actions,
                reasons: candidate.reasons,
                targetName: candidate.pod.targets.count == 1 ? candidate.pod.targets[0] : nil,
                packageCandidate: candidate.packageCandidate
            )
        }

        return PkgLiftCore.MigrationPlan(
            projectPath: projectPath,
            entries: entries,
            issues: candidates.flatMap { $0.issues },
            readinessScore: migrationReadinessScore()
        )
    }

    func buildProjectAnalysis() -> ProjectAnalysis {
        let candidates = migrationCandidates(includeTransitive: true)

        let swiftPMState = xcodeAnalysis?.swiftPMState ?? SwiftPMState()
        let analyzedProjectInfo = xcodeAnalysis?.projectInfo ?? ProjectInfo(
            projectPath: resolvedProjectPath ?? discovery.rootPath,
            workspacePath: resolvedWorkspacePath,
            targets: []
        )
        let projectInfo = ProjectInfo(
            projectPath: analyzedProjectInfo.projectPath,
            workspacePath: resolvedWorkspacePath,
            targets: analyzedProjectInfo.targets
        )

        return ProjectAnalysis(
            project: projectInfo,
            cocoaPods: CocoaPodsState(
                directDependencies: directDependencies,
                transitiveDependencies: transitiveDependencies,
                hasPodfile: discovery.podfilePath != nil,
                hasPodfileLock: discovery.podfileLockPath != nil,
                hasManifestLock: discovery.manifestLockPath != nil,
                podfileFeatures: podfileFeatures
            ),
            swiftPM: swiftPMState,
            candidates: candidates,
            issues: candidates.flatMap(\.issues),
            readinessScore: migrationReadinessScore()
        )
    }

    static func load(from options: CommonOptions) async throws -> CommandContext {
        let discovery = try FileDiscovery().discover(in: options.path)

        let configPath = discovery.configPath
        let configuration: PkgLiftConfiguration
        if let configPath {
            configuration = try ConfigurationLoader().load(from: configPath)
        } else {
            configuration = .default
        }

        let additionalPaths = configuration.registry?.additionalPaths ?? []
        let configURLs = additionalPaths.compactMap { path in
            let fullPath = resolvePath(path, base: discovery.rootPath)
            return URL(fileURLWithPath: fullPath)
        }

        let localOverrideURL: URL?
        if let local = discovery.localRegistryPath {
            localOverrideURL = URL(fileURLWithPath: local)
        } else {
            localOverrideURL = nil
        }

        let registryLoader = RegistryLoader(
            configPaths: configURLs,
            localOverridePath: localOverrideURL,
            useBundledRegistry: true
        )
        try await registryLoader.load()
        var mappingByName: [String: RegistryMapping] = [:]
        for mapping in await registryLoader.getMappings() {
            mappingByName[mapping.pod.fullName] = mapping
            if mapping.pod.subspec == nil {
                mappingByName[mapping.pod.name] = mapping
            }
        }

        let parser = PodfileParser()
        var features = PodfileFeatures()
        var directDependencies: [CocoaPodDependency] = []
        var podfileContent: String?

        if let podfilePath = discovery.podfilePath {
            let podfileURL = URL(fileURLWithPath: podfilePath)
            let parsed = try parser.parse(fileURL: podfileURL)
            features = parsed.features
            directDependencies = parsed.directDependencies
            podfileContent = try String(contentsOf: podfileURL)
        }

        let lockParser = PodfileLockParser()
        let mapper = PodfileTargetMapper()
        var mappedDependencies: [CocoaPodDependency] = []

        if let lockPath = discovery.podfileLockPath {
            let lockDeps = try lockParser.parse(fileURL: URL(fileURLWithPath: lockPath))
            if let podfileContent = podfileContent {
                mappedDependencies = mapper.map(podfileContent: podfileContent, lockfileDependencies: lockDeps)
            } else {
                mappedDependencies = lockDeps
            }
        } else {
            mappedDependencies = directDependencies
        }

        if !mappedDependencies.isEmpty {
            directDependencies = directDependencies.map { declaration in
                let resolved = mappedDependencies.first { $0.name == declaration.name }

                guard let resolved else { return declaration }
                return CocoaPodDependency(
                    name: declaration.name,
                    version: resolved.version,
                    source: resolved.source,
                    isDirect: true,
                    targets: resolved.targets
                )
            }
        }

        let selection = try resolveXcodeTarget(
            projectOverride: options.project,
            workspaceOverride: options.workspace,
            rootPath: discovery.rootPath,
            discoveredWorkspacePaths: discovery.workspacePaths,
            discoveredProjectPaths: discovery.projectPaths
        )

        return CommandContext(
            discovery: discovery,
            configuration: configuration,
            podfileFeatures: features,
            podfileContent: podfileContent,
            directDependencies: directDependencies,
            mappedDependencies: mappedDependencies,
            registryMappings: mappingByName,
            resolvedProjectPath: selection.projectPath,
            resolvedWorkspacePath: selection.workspacePath,
            isWorkspaceSelected: selection.selectedWorkspace,
            xcodeAnalysis: selection.analysis
        )
    }

    private static func resolveXcodeTarget(
        projectOverride: String?,
        workspaceOverride: String?,
        rootPath: String,
        discoveredWorkspacePaths: [String],
        discoveredProjectPaths: [String]
    ) throws -> (projectPath: String?, workspacePath: String?, selectedWorkspace: Bool, analysis: XcodeAnalysisResult?) {
        if let explicitWorkspace = workspaceOverride {
            let workspacePath = try resolveSelectedPath(
                explicitWorkspace,
                expectedExtension: "xcworkspace",
                rootPath: rootPath
            )
            let explicitProjectPath = try projectOverride.map {
                try resolveSelectedPath(
                    $0,
                    expectedExtension: "xcodeproj",
                    rootPath: rootPath
                )
            }
            let (projectPath, analysis) = try resolveProject(
                fromWorkspace: workspacePath,
                rootPath: rootPath,
                explicitProjectPath: explicitProjectPath
            )
            return (projectPath, workspacePath, true, analysis)
        }

        if let explicitProject = projectOverride {
            let resolved = try resolveSelectedPath(
                explicitProject,
                expectedExtension: "xcodeproj",
                rootPath: rootPath
            )
            let analyzer = XcodeProjectAnalyzer()
            let analysis = try analyzer.analyzeProject(at: resolved)
            return (resolved, nil, false, analysis)
        }

        if discoveredWorkspacePaths.count > 1 {
            throw CommandContextError.ambiguousWorkspaces(discoveredWorkspacePaths)
        }

        if let workspacePath = discoveredWorkspacePaths.first {
            let (projectPath, analysis) = try resolveProject(
                fromWorkspace: workspacePath,
                rootPath: rootPath,
                explicitProjectPath: nil
            )
            return (projectPath, workspacePath, true, analysis)
        }

        if discoveredProjectPaths.count > 1 {
            throw CommandContextError.ambiguousProjects(discoveredProjectPaths)
        }

        if let projectPath = discoveredProjectPaths.first {
            let resolved = try resolveSelectedPath(
                projectPath,
                expectedExtension: "xcodeproj",
                rootPath: rootPath
            )
            let analyzer = XcodeProjectAnalyzer()
            let analysis = try analyzer.analyzeProject(at: resolved)
            return (resolved, nil, false, analysis)
        }

        return (nil, nil, false, nil)
    }

    private static func resolveProject(
        fromWorkspace workspacePath: String,
        rootPath: String,
        explicitProjectPath: String?
    ) throws -> (String, XcodeAnalysisResult) {
        let analyzer = WorkspaceAnalyzer()
        let result = try analyzer.analyzeWorkspace(
            at: workspacePath,
            containedIn: rootPath
        )
        let candidates = result.projectPaths

        if let explicitProjectPath {
            guard candidates.contains(explicitProjectPath) else {
                throw CommandContextError.projectNotInWorkspace(
                    project: explicitProjectPath,
                    workspace: workspacePath,
                    projects: candidates
                )
            }

            let analysis = try XcodeProjectAnalyzer().analyzeProject(at: explicitProjectPath)
            return (explicitProjectPath, analysis)
        }

        guard candidates.count == 1, let projectPath = candidates.first else {
            throw CommandContextError.ambiguousWorkspaceProjects(
                workspace: workspacePath,
                projects: candidates
            )
        }

        let xcodeResult = try XcodeProjectAnalyzer().analyzeProject(at: projectPath)
        return (projectPath, xcodeResult)
    }

    private static func resolveSelectedPath(
        _ path: String,
        expectedExtension: String,
        rootPath: String
    ) throws -> String {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardized
            .resolvingSymlinksInPath()
        let candidate = path.hasPrefix("/")
            ? URL(fileURLWithPath: path, isDirectory: true)
            : rootURL.appendingPathComponent(path, isDirectory: true)
        let resolved = candidate.standardized.resolvingSymlinksInPath()

        let isContained = rootURL.path == "/"
            ? resolved.path.hasPrefix("/")
            : resolved.path == rootURL.path || resolved.path.hasPrefix(rootURL.path + "/")
        guard isContained else {
            throw CommandContextError.selectionOutsideRoot(
                path: path,
                resolved: resolved.path,
                root: rootURL.path
            )
        }
        guard resolved.pathExtension == expectedExtension else {
            throw CommandContextError.invalidSelectionExtension(
                path: resolved.path,
                expectedExtension: expectedExtension
            )
        }
        return resolved.path
    }
}

private func existingPackage(
    matching repositoryURL: String,
    in packages: [SwiftPMDependency]
) -> SwiftPMDependency? {
    let identity = RepositoryIdentity.normalized(repositoryURL)
    return packages.first { RepositoryIdentity.normalized($0.repositoryURL) == identity }
}

enum CommandContextError: LocalizedError {
    case ambiguousWorkspaces([String])
    case ambiguousProjects([String])
    case ambiguousWorkspaceProjects(workspace: String, projects: [String])
    case projectNotInWorkspace(project: String, workspace: String, projects: [String])
    case selectionOutsideRoot(path: String, resolved: String, root: String)
    case invalidSelectionExtension(path: String, expectedExtension: String)

    var errorDescription: String? {
        switch self {
        case .ambiguousWorkspaces(let paths):
            return "Multiple Xcode workspaces were found (\(paths.joined(separator: ", "))). Use --workspace to choose one explicitly."
        case .ambiguousProjects(let paths):
            return "Multiple Xcode projects were found (\(paths.joined(separator: ", "))). Use --project to choose one explicitly."
        case .ambiguousWorkspaceProjects(let workspace, let projects):
            let detail = projects.isEmpty ? "no non-Pods project" : projects.joined(separator: ", ")
            return "Workspace '\(workspace)' does not resolve to exactly one application project (\(detail)). Use --workspace together with --project to choose explicitly."
        case .projectNotInWorkspace(let project, let workspace, let projects):
            let detail = projects.isEmpty ? "no selectable projects" : projects.joined(separator: ", ")
            return "Project '\(project)' is not referenced by workspace '\(workspace)' (\(detail))."
        case .selectionOutsideRoot(let path, let resolved, let root):
            return "Selected path '\(path)' resolves to '\(resolved)', outside the project root '\(root)'."
        case .invalidSelectionExtension(let path, let expectedExtension):
            return "Selected path '\(path)' must have the .\(expectedExtension) extension."
        }
    }
}

private func resolvePath(_ path: String, base: String) -> String {
    if path.hasPrefix("/") {
        return path
    }
    return URL(fileURLWithPath: base).appendingPathComponent(path).path
}
