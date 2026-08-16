import Foundation

/// Stable status for a diagnostics report.
public enum DiagnosticsReportStatus: String, Sendable, Codable, Equatable {
    case complete
    case partial
}

/// A stage that could not be inspected while creating diagnostics.
public enum DiagnosticsFailureStage: String, Sendable, Codable, Equatable, CaseIterable {
    case discovery
    case git
    case analysis
    case environment
}

/// A deliberately minimal failure record.
///
/// The concrete error type is retained for triage, but arbitrary error text is
/// excluded because it may contain paths, project names, package URLs, or other
/// private input.
public struct DiagnosticsFailure: Sendable, Codable, Equatable {
    public let stage: DiagnosticsFailureStage
    public let type: String

    public init(stage: DiagnosticsFailureStage, type: String) {
        self.stage = stage
        self.type = Self.sanitizedType(type)
    }

    public init(stage: DiagnosticsFailureStage, error: any Error) {
        self.init(stage: stage, type: String(reflecting: Swift.type(of: error)))
    }

    private static func sanitizedType(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._<>"))
        let scalars = value.unicodeScalars.filter { allowed.contains($0) }
        let sanitized = String(String.UnicodeScalarView(scalars))
        return String((sanitized.isEmpty ? "UnknownError" : sanitized).prefix(160))
    }
}

/// Toolchain versions that do not identify the project or user.
public struct DiagnosticsEnvironmentSummary: Sendable, Codable, Equatable {
    public let macOS: String
    public let xcode: String?
    public let swift: String?
    public let cocoaPods: String?

    public init(macOS: String, xcode: String?, swift: String?, cocoaPods: String?) {
        self.macOS = macOS
        self.xcode = xcode
        self.swift = swift
        self.cocoaPods = cocoaPods
    }
}

public enum DiagnosticsSelectionKind: String, Sendable, Codable, Equatable {
    case none
    case project
    case workspace
}

/// Project shape without repository, project, workspace, scheme, or target names.
public struct DiagnosticsProjectSummary: Sendable, Codable, Equatable {
    public let root: String
    public let discoveredProjectCount: Int
    public let discoveredWorkspaceCount: Int
    public let selection: DiagnosticsSelectionKind
    public let targetCount: Int?
    public let integrations: [ProjectIntegration]
    public let integrationCount: Int

    public init(
        discoveredProjectCount: Int,
        discoveredWorkspaceCount: Int,
        selection: DiagnosticsSelectionKind,
        targetCount: Int?,
        integrations: [ProjectIntegration] = []
    ) {
        self.root = "<PROJECT_ROOT>"
        self.discoveredProjectCount = discoveredProjectCount
        self.discoveredWorkspaceCount = discoveredWorkspaceCount
        self.selection = selection
        self.targetCount = targetCount
        self.integrations = Array(Set(integrations)).sorted()
        self.integrationCount = self.integrations.count
    }
}

/// Boolean Podfile features that affect migration safety.
public struct DiagnosticsPodfileFeaturesSummary: Sendable, Codable, Equatable {
    public let useFrameworks: Bool
    public let useModularHeaders: Bool
    public let hasPostInstallHook: Bool
    public let hasPreInstallHook: Bool
    public let hasScriptPhase: Bool
    public let hasDynamicRuby: Bool
    public let hasInheritSearchPaths: Bool
    public let hasAbstractTargets: Bool

    public init(_ features: PodfileFeatures) {
        self.useFrameworks = features.useFrameworks
        self.useModularHeaders = features.useModularHeaders
        self.hasPostInstallHook = features.hasPostInstallHook
        self.hasPreInstallHook = features.hasPreInstallHook
        self.hasScriptPhase = features.hasScriptPhase
        self.hasDynamicRuby = features.hasDynamicRuby
        self.hasInheritSearchPaths = features.hasInheritSearchPaths
        self.hasAbstractTargets = features.hasAbstractTargets
    }
}

/// CocoaPods state represented only as counts and safety flags.
public struct DiagnosticsCocoaPodsSummary: Sendable, Codable, Equatable {
    public let hasPodfile: Bool
    public let hasPodfileLock: Bool
    public let hasManifestLock: Bool
    public let directDependencyCount: Int?
    public let transitiveDependencyCount: Int?
    public let features: DiagnosticsPodfileFeaturesSummary?

    public init(
        hasPodfile: Bool,
        hasPodfileLock: Bool,
        hasManifestLock: Bool,
        directDependencyCount: Int?,
        transitiveDependencyCount: Int?,
        features: DiagnosticsPodfileFeaturesSummary?
    ) {
        self.hasPodfile = hasPodfile
        self.hasPodfileLock = hasPodfileLock
        self.hasManifestLock = hasManifestLock
        self.directDependencyCount = directDependencyCount
        self.transitiveDependencyCount = transitiveDependencyCount
        self.features = features
    }
}

public struct DiagnosticsSwiftPMSummary: Sendable, Codable, Equatable {
    public let existingPackageCount: Int
    public let hasPackageResolved: Bool

    public init(existingPackageCount: Int, hasPackageResolved: Bool) {
        self.existingPackageCount = existingPackageCount
        self.hasPackageResolved = hasPackageResolved
    }
}

public struct DiagnosticsClassificationSummary: Sendable, Codable, Equatable {
    public let auto: Int
    public let review: Int
    public let blocked: Int
    public let unknown: Int

    public init(candidates: [MigrationCandidate]) {
        self.auto = candidates.count { $0.classification == .auto }
        self.review = candidates.count { $0.classification == .review }
        self.blocked = candidates.count { $0.classification == .blocked }
        self.unknown = candidates.count { $0.classification == .unknown }
    }
}

public struct DiagnosticsIssueSummary: Sendable, Codable, Equatable {
    public let info: Int
    public let warning: Int
    public let error: Int

    public init(issues: [MigrationIssue]) {
        self.info = issues.count { $0.severity == .info }
        self.warning = issues.count { $0.severity == .warning }
        self.error = issues.count { $0.severity == .error }
    }
}

public enum DiagnosticsGitState: String, Sendable, Codable, Equatable {
    case unknown
    case notRepository
    case clean
    case dirty
}

/// Git state without changed filenames or repository remotes.
public struct DiagnosticsGitSummary: Sendable, Codable, Equatable {
    public let state: DiagnosticsGitState
    public let changedFileCount: Int?

    public init(state: DiagnosticsGitState, changedFileCount: Int? = nil) {
        self.state = state
        self.changedFileCount = changedFileCount
    }

    public static let unknown = DiagnosticsGitSummary(state: .unknown)
}

/// Explicit privacy contract encoded into every report.
public struct DiagnosticsPrivacySummary: Sendable, Codable, Equatable {
    public let redactionEnabled: Bool
    public let containsSourceCode: Bool
    public let containsPodfileContents: Bool
    public let containsDependencyNames: Bool
    public let containsProjectOrTargetNames: Bool
    public let containsRepositoryOrPackageURLs: Bool
    public let containsAbsoluteUserPaths: Bool
    public let automaticUpload: Bool

    public init() {
        self.redactionEnabled = true
        self.containsSourceCode = false
        self.containsPodfileContents = false
        self.containsDependencyNames = false
        self.containsProjectOrTargetNames = false
        self.containsRepositoryOrPackageURLs = false
        self.containsAbsoluteUserPaths = false
        self.automaticUpload = false
    }
}

/// Versioned, deterministic, privacy-preserving diagnostics output.
public struct DiagnosticsReport: Sendable, Codable, Equatable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let pkgLiftVersion: String
    public let status: DiagnosticsReportStatus
    public let environment: DiagnosticsEnvironmentSummary
    public let project: DiagnosticsProjectSummary
    public let cocoaPods: DiagnosticsCocoaPodsSummary
    public let swiftPM: DiagnosticsSwiftPMSummary?
    public let classifications: DiagnosticsClassificationSummary?
    public let issues: DiagnosticsIssueSummary?
    public let readinessScore: Int?
    public let git: DiagnosticsGitSummary
    public let failures: [DiagnosticsFailure]
    public let privacy: DiagnosticsPrivacySummary

    public init(
        status: DiagnosticsReportStatus,
        environment: DiagnosticsEnvironmentSummary,
        project: DiagnosticsProjectSummary,
        cocoaPods: DiagnosticsCocoaPodsSummary,
        swiftPM: DiagnosticsSwiftPMSummary?,
        classifications: DiagnosticsClassificationSummary?,
        issues: DiagnosticsIssueSummary?,
        readinessScore: Int?,
        git: DiagnosticsGitSummary,
        failures: [DiagnosticsFailure]
    ) {
        self.schemaVersion = Self.schemaVersion
        self.pkgLiftVersion = PkgLiftCore.pkgLiftVersion
        self.status = status
        self.environment = environment
        self.project = project
        self.cocoaPods = cocoaPods
        self.swiftPM = swiftPM
        self.classifications = classifications
        self.issues = issues
        self.readinessScore = readinessScore
        self.git = git
        self.failures = failures
        self.privacy = DiagnosticsPrivacySummary()
    }
}

/// Converts rich analysis models into a report containing only counts and flags.
public struct DiagnosticsReportBuilder: Sendable {
    public init() {}

    public func build(
        environment: DiagnosticsEnvironmentSummary,
        discovery: DiscoveredFiles?,
        analysis: ProjectAnalysis?,
        git: DiagnosticsGitSummary,
        failures: [DiagnosticsFailure]
    ) -> DiagnosticsReport {
        let selection: DiagnosticsSelectionKind
        if let analysis {
            selection = analysis.project.workspacePath == nil ? .project : .workspace
        } else {
            selection = .none
        }

        var integrations = Set(analysis?.detectedIntegrations ?? [])
        if discovery?.hasCarthageFiles == true {
            integrations.insert(.carthage)
        }

        let project = DiagnosticsProjectSummary(
            discoveredProjectCount: discovery?.projectPaths.count ?? 0,
            discoveredWorkspaceCount: discovery?.workspacePaths.count ?? 0,
            selection: selection,
            targetCount: analysis?.project.targets.count,
            integrations: integrations.sorted()
        )

        let cocoaPods = DiagnosticsCocoaPodsSummary(
            hasPodfile: analysis?.cocoaPods.hasPodfile ?? (discovery?.podfilePath != nil),
            hasPodfileLock: analysis?.cocoaPods.hasPodfileLock ?? (discovery?.podfileLockPath != nil),
            hasManifestLock: analysis?.cocoaPods.hasManifestLock ?? (discovery?.manifestLockPath != nil),
            directDependencyCount: analysis.map {
                $0.counts?.uniqueDirectDependencyCount
                    ?? $0.cocoaPods.directDependencies.count
            },
            transitiveDependencyCount: analysis?.cocoaPods.transitiveDependencies.count,
            features: analysis.map { DiagnosticsPodfileFeaturesSummary($0.cocoaPods.podfileFeatures) }
        )

        let swiftPM = analysis.map {
            DiagnosticsSwiftPMSummary(
                existingPackageCount: $0.swiftPM.packages.count,
                hasPackageResolved: $0.swiftPM.hasPackageResolved
            )
        }
        let classifications = analysis.map { DiagnosticsClassificationSummary(candidates: $0.candidates) }
        let issues = analysis.map { DiagnosticsIssueSummary(issues: $0.issues) }

        let orderedFailures = failures.sorted {
            if $0.stage.rawValue == $1.stage.rawValue {
                return $0.type < $1.type
            }
            return $0.stage.rawValue < $1.stage.rawValue
        }

        return DiagnosticsReport(
            status: analysis != nil && orderedFailures.isEmpty ? .complete : .partial,
            environment: environment,
            project: project,
            cocoaPods: cocoaPods,
            swiftPM: swiftPM,
            classifications: classifications,
            issues: issues,
            readinessScore: analysis?.readinessScore,
            git: git,
            failures: orderedFailures
        )
    }
}

/// Encodes and writes diagnostics without silently replacing an existing file.
public struct DiagnosticsReportWriter: Sendable {
    public init() {}

    public func encode(_ report: DiagnosticsReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }

    public func write(
        _ report: DiagnosticsReport,
        to outputURL: URL,
        overwrite: Bool
    ) throws {
        let fileManager = FileManager.default
        let parentURL = outputURL.deletingLastPathComponent()

        var parentIsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: parentURL.path, isDirectory: &parentIsDirectory) {
            guard parentIsDirectory.boolValue else {
                throw DiagnosticsReportWriterError.parentIsNotDirectory(parentURL.path)
            }
        } else {
            try fileManager.createDirectory(
                at: parentURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        // Check the directory entry itself before following the destination.
        // `fileExists` returns false for a dangling link, so checking only the
        // target would allow the atomic write to replace that link.
        if (try? fileManager.destinationOfSymbolicLink(atPath: outputURL.path)) != nil {
            throw DiagnosticsReportWriterError.outputIsSymbolicLink(outputURL.path)
        }

        var outputIsDirectory: ObjCBool = false
        let outputExists = fileManager.fileExists(
            atPath: outputURL.path,
            isDirectory: &outputIsDirectory
        )

        if outputExists {
            if outputIsDirectory.boolValue {
                throw DiagnosticsReportWriterError.outputIsDirectory(outputURL.path)
            }
            guard overwrite else {
                throw DiagnosticsReportWriterError.outputExists(outputURL.path)
            }
        }

        try encode(report).write(to: outputURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: outputURL.path
        )
    }
}

public enum DiagnosticsReportWriterError: LocalizedError, Sendable, Equatable {
    case parentIsNotDirectory(String)
    case outputIsDirectory(String)
    case outputIsSymbolicLink(String)
    case outputExists(String)

    public var errorDescription: String? {
        switch self {
        case .parentIsNotDirectory(let path):
            return "Diagnostics output parent is not a directory: \(path)"
        case .outputIsDirectory(let path):
            return "Diagnostics output points to a directory: \(path)"
        case .outputIsSymbolicLink(let path):
            return "Diagnostics output refuses to replace a symbolic link: \(path)"
        case .outputExists(let path):
            return "Diagnostics output already exists: \(path). Add --overwrite to replace it."
        }
    }
}
