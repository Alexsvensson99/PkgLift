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
    /// Literal Podfile declarations, including repeated names.
    let directDependencies: [CocoaPodDependency]
    /// One entry per exact direct dependency name, with declaration evidence retained.
    let uniqueDirectDependencies: [CocoaPodDependency]
    /// One entry per exact lockfile dependency name.
    let lockfileDependencies: [CocoaPodDependency]
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
        lockfileDependencies.filter { !$0.isDirect }
    }

    var analysisDependencies: [CocoaPodDependency] {
        guard discovery.podfileLockPath != nil else {
            return uniqueDirectDependencies
        }
        let lockfileNames = Set(lockfileDependencies.map(\.name))
        return lockfileDependencies + uniqueDirectDependencies.filter {
            !lockfileNames.contains($0.name)
        }
    }

    var dependencyCounts: DependencyCounts {
        DependencyCounts(
            literalPodfileDeclarationCount: directDependencies.count,
            uniqueDirectDependencyCount: uniqueDirectDependencies.count,
            uniqueLockfileDependencyCount: lockfileDependencies.count,
            planEntryCount: uniqueDirectDependencies.count,
            analysisCandidateCount: analysisDependencies.count
        )
    }

    var projectPath: String {
        resolvedProjectPath ?? discovery.rootPath
    }

    var detectedProjectIntegrations: [ProjectIntegration] {
        var integrations = Set(podfileFeatures.integrationMarkers)
        if discovery.hasCarthageFiles || xcodeAnalysis?.hasCarthageIntegration == true {
            integrations.insert(.carthage)
        }
        return integrations.sorted()
    }

    var projectIntegrationIssues: [MigrationIssue] {
        detectedProjectIntegrations.map {
            MigrationIssue(severity: .warning, message: $0.reviewReason)
        }
    }

    func mappedDependency(for name: String) -> CocoaPodDependency? {
        analysisDependencies.first(where: { $0.name == name })
    }

    func exactTargetInfo(for dependency: CocoaPodDependency) -> TargetInfo? {
        let attribution = dependency.effectiveTargetAttribution
        guard attribution.status == .exact,
              attribution.targets.count == 1,
              let targetName = attribution.targets.first,
              let targets = xcodeAnalysis?.projectInfo.targets else { return nil }
        let matches = targets.filter { $0.name == targetName }
        return matches.count == 1 ? matches.first : nil
    }

    func migrationCandidates(includeTransitive: Bool = false) -> [PkgLiftCore.MigrationCandidate] {
        let classifier = MigrationClassifier()
        let versionMapper = VersionMapper()

        let dependencies = includeTransitive ? analysisDependencies : uniqueDirectDependencies

        let candidates = dependencies.map { dependency -> PkgLiftCore.MigrationCandidate in
            let mapping = registryMappings[dependency.name]

            let isAlreadyMigrated: Bool = {
                guard let mapping = mapping else { return false }
                guard let packages = xcodeAnalysis?.swiftPMState.packages else { return false }

                return packages.contains {
                    $0.repositoryURL.caseInsensitiveCompare(mapping.swiftpm.repository) == .orderedSame
                }
            }()

            let targetInfo = exactTargetInfo(for: dependency)

            let result = classifier.classify(
                dependency: dependency,
                mapping: mapping,
                isAlreadyMigrated: isAlreadyMigrated,
                isTargetMappingKnown: targetInfo != nil,
                targetSourceProfile: targetInfo?.sourceProfile,
                projectIntegrations: detectedProjectIntegrations,
                podfileFeatures: podfileFeatures
            )

            var coreClassification = result.category
            var reasons = result.reasons

            let denied = configuration.migration?.deny ?? []
            let allowed = configuration.migration?.allow
            if denied.contains(dependency.name) || denied.contains(dependency.baseName) {
                coreClassification = .blocked
                reasons.insert("Dependency is denied by .pkglift.yml", at: 0)
            } else if let allowed,
                      !allowed.contains(dependency.name),
                      !allowed.contains(dependency.baseName) {
                if coreClassification != .blocked {
                    coreClassification = .review
                }
                reasons.insert(
                    "Dependency is not in the .pkglift.yml migration allow list",
                    at: 0
                )
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
                    confidence: mapping.migration.confidence,
                    supportedConsumerLanguages: mapping.swiftpm.supportedConsumerLanguages
                )
            } else {
                mappedPackage = nil
            }

            if coreClassification == .auto,
               (mappedPackage?.versionRequirement == nil ||
                mappedPackage?.products.isEmpty != false ||
                !dependency.hasLiteralMigrationProvenance ||
                dependency.targets.count != 1 ||
                targetInfo == nil ||
                !hasCompatibleLanguageEvidence(
                    profile: targetInfo?.sourceProfile,
                    supportedLanguages: mappedPackage?.supportedConsumerLanguages
                )) {
                coreClassification = .review
                reasons.append("Automatic migration data is incomplete or ambiguous")
            }

            if let mappedPackage,
               let existingPackage = existingPackage(
                    matching: mappedPackage.repositoryURL,
                    in: xcodeAnalysis?.swiftPMState.packages ?? []
               ),
               existingPackage.requirement != mappedPackage.versionRequirement {
                if coreClassification == .auto {
                    coreClassification = .review
                }
                reasons.append("Existing SwiftPM package uses a different or unknown version requirement")
            }

            if result.category == .auto, coreClassification != .auto {
                let successfulAutoEvidence = Set(result.reasons)
                reasons.removeAll { successfulAutoEvidence.contains($0) }
            }
            reasons = stableDeduplicated(reasons)
            let issues: [MigrationIssue]
            if coreClassification == .auto {
                issues = []
            } else {
                let severity: MigrationIssue.Severity = coreClassification == .blocked
                    ? .error
                    : .warning
                let primaryReason = reasons.first ?? "Manual review is required"
                issues = [MigrationIssue(
                    severity: severity,
                    message: primaryReason,
                    detail: reasons.count > 1
                        ? reasons.dropFirst().joined(separator: ". ")
                        : nil,
                    dependency: dependency.name
                )]
            }

            return PkgLiftCore.MigrationCandidate(
                pod: dependency,
                classification: coreClassification,
                packageCandidate: mappedPackage,
                reasons: reasons,
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
            totalDirectCount: uniqueDirectDependencies.count,
            blockedDirectCount: candidates.filter { $0.classification == .blocked }.count,
            hasPostInstallHook: podfileFeatures.hasPostInstallHook,
            hasPreInstallHook: podfileFeatures.hasPreInstallHook,
            hasScriptPhase: podfileFeatures.hasScriptPhase,
            hasDynamicRuby: podfileFeatures.hasDynamicRuby,
            noProjectRisks: !podfileFeatures.hasDynamicRuby &&
                !podfileFeatures.hasPostInstallHook &&
                !podfileFeatures.hasPreInstallHook &&
                !podfileFeatures.hasScriptPhase &&
                detectedProjectIntegrations.isEmpty
        )
    }

    func buildMigrationPlan() -> PkgLiftCore.MigrationPlan {
        let candidates = migrationCandidates()

        let entries: [PkgLiftCore.MigrationPlanEntry] = candidates.map { candidate in
            var actions: [PkgLiftCore.MigrationAction] = []

            let attribution = candidate.pod.effectiveTargetAttribution
            let targetName = attribution.status == .exact && attribution.targets.count == 1
                ? attribution.targets[0]
                : nil
            let targetSourceProfile = exactTargetInfo(for: candidate.pod)?.sourceProfile

            if let packageCandidate = candidate.packageCandidate,
               let requirement = packageCandidate.versionRequirement,
               let targetName,
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
                let description = candidate.packageCandidate == nil
                    ? "No exact executable registry mapping is available; see reasons."
                    : "Automatic migration is refused; manual review is required for the listed safety reasons."
                actions.append(
                    .manual(
                        description: description
                    )
                )
            }

            return PkgLiftCore.MigrationPlanEntry(
                podName: candidate.pod.name,
                currentVersion: candidate.pod.version,
                classification: candidate.classification,
                actions: actions,
                reasons: candidate.reasons,
                targetName: targetName,
                packageCandidate: candidate.packageCandidate,
                declarations: candidate.pod.declarations,
                targetAttribution: attribution,
                targetSourceProfile: targetSourceProfile
            )
        }

        return PkgLiftCore.MigrationPlan(
            projectPath: projectPath,
            entries: entries,
            issues: projectIntegrationIssues + candidates.flatMap { $0.issues },
            readinessScore: migrationReadinessScore(),
            counts: dependencyCounts
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
            issues: projectIntegrationIssues + candidates.flatMap(\.issues),
            readinessScore: migrationReadinessScore(),
            counts: dependencyCounts,
            detectedIntegrations: detectedProjectIntegrations
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
        var parsedDeclarations: [CocoaPodDependency] = []
        var podfileContent: String?

        if let podfilePath = discovery.podfilePath {
            let podfileURL = URL(fileURLWithPath: podfilePath)
            let parsed = try parser.parse(fileURL: podfileURL)
            features = parsed.features
            parsedDeclarations = parsed.directDependencies
            podfileContent = try String(contentsOf: podfileURL, encoding: .utf8)
        }

        let lockParser = PodfileLockParser()
        let mapper = PodfileTargetMapper()
        var parsedLockfileDependencies: [CocoaPodDependency] = []

        if let lockPath = discovery.podfileLockPath {
            parsedLockfileDependencies = try lockParser.parse(
                fileURL: URL(fileURLWithPath: lockPath)
            )
        }

        let directDependencies = mapper.mapDeclarations(
            parsedDeclarations,
            lockfileDependencies: parsedLockfileDependencies
        )
        let uniqueDirectDependencies = mapper.aggregateDirectDependencies(directDependencies)
        let lockfileDependencies = mapper.mapLockfileDependencies(
            parsedLockfileDependencies,
            declarations: directDependencies
        )

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
            uniqueDirectDependencies: uniqueDirectDependencies,
            lockfileDependencies: lockfileDependencies,
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
            let analysis = try analyzer.analyzeProject(at: resolved, containedIn: rootPath)
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
            let analysis = try analyzer.analyzeProject(at: resolved, containedIn: rootPath)
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

            let analysis = try XcodeProjectAnalyzer().analyzeProject(
                at: explicitProjectPath,
                containedIn: rootPath
            )
            return (explicitProjectPath, analysis)
        }

        guard candidates.count == 1, let projectPath = candidates.first else {
            throw CommandContextError.ambiguousWorkspaceProjects(
                workspace: workspacePath,
                projects: candidates
            )
        }

        let xcodeResult = try XcodeProjectAnalyzer().analyzeProject(
            at: projectPath,
            containedIn: rootPath
        )
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

private func hasCompatibleLanguageEvidence(
    profile: TargetSourceProfile?,
    supportedLanguages: [SourceLanguage]?
) -> Bool {
    guard let profile,
          profile.completeness == .complete,
          !profile.languages.isEmpty,
          let supportedLanguages,
          !supportedLanguages.isEmpty,
          Set(supportedLanguages).count == supportedLanguages.count else {
        return false
    }
    return Set(profile.languages).isSubset(of: Set(supportedLanguages))
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

private func stableDeduplicated(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
}
