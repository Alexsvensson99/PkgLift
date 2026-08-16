//
//  MigrationPlanner.swift
//  PkgLiftMigration
//

import Foundation
import PkgLiftCore

public typealias MigrationAction = PkgLiftCore.MigrationAction
public typealias MigrationPlanEntry = PkgLiftCore.MigrationPlanEntry
public typealias MigrationPlan = PkgLiftCore.MigrationPlan

/// Generates migration plans.
public struct MigrationPlanner: Sendable {
    
    public init() {}
    
    public func generatePlan(
        dependencies: [String: CocoaPodDependency],
        mappings: [String: RegistryMapping],
        projectPath: String = ".",
        podfileFeatures: PodfileFeatures = PodfileFeatures(),
        availableTargets: [String] = [],
        availableTargetInfos: [TargetInfo] = [],
        projectIntegrations: [ProjectIntegration] = [],
        counts: DependencyCounts? = nil
    ) -> MigrationPlan {
        var entries: [MigrationPlanEntry] = []
        let detectedIntegrations = Array(Set(
            projectIntegrations + podfileFeatures.integrationMarkers
        )).sorted()
        var issues: [MigrationIssue] = detectedIntegrations.map {
            MigrationIssue(severity: .warning, message: $0.reviewReason)
        }
        let classifier = MigrationClassifier()
        var autoCount = 0
        
        for podName in dependencies.keys.sorted() {
            guard let dep = dependencies[podName] else { continue }
            let mapping = mappings[podName]
            let attribution = dep.effectiveTargetAttribution
            let targetName = attribution.status == .exact
                ? attribution.targets.first
                : nil
            let targetIsKnown = targetName.map { target in
                if availableTargetInfos.isEmpty {
                    return availableTargets.filter { $0 == target }.count == 1
                }
                return availableTargetInfos.filter { $0.name == target }.count == 1
            } ?? false
            let targetSourceProfile = targetName.flatMap { target in
                let matches = availableTargetInfos.filter { $0.name == target }
                return matches.count == 1 ? matches[0].sourceProfile : nil
            }
            let classification = classifier.classify(
                dependency: dep,
                mapping: mapping,
                isTargetMappingKnown: targetIsKnown,
                targetSourceProfile: targetSourceProfile,
                projectIntegrations: detectedIntegrations,
                podfileFeatures: podfileFeatures
            )

            let versionRequirement = dep.version.flatMap { version -> SwiftPMVersionRequirement? in
                guard let mapped = VersionMapper().map(constraint: version, resolvedVersion: version) else {
                    return nil
                }
                switch mapped {
                case .exact(let value): return .exact(value)
                case .from(let value): return .from(value)
                case .upToNextMinor(let value): return .upToNextMinor(value)
                }
            }

            let packageCandidate = mapping.map {
                PackageCandidate(
                    repositoryURL: $0.swiftpm.repository,
                    products: $0.swiftpm.products,
                    versionRequirement: versionRequirement,
                    confidence: $0.migration.confidence,
                    supportedConsumerLanguages: $0.swiftpm.supportedConsumerLanguages
                )
            }
            
            var actions: [MigrationAction] = []
            if classification.category == .auto,
               let packageCandidate,
               let requirement = packageCandidate.versionRequirement,
               let targetName {
                autoCount += 1
                actions = [
                    .removePod(name: podName),
                    .addSwiftPackage(
                        repositoryURL: packageCandidate.repositoryURL,
                        requirement: requirement
                    ),
                ]
                actions.append(contentsOf: packageCandidate.products.map {
                    .linkProduct(
                        repositoryURL: packageCandidate.repositoryURL,
                        productName: $0,
                        targetName: targetName
                    )
                })
            } else {
                let severity: MigrationIssue.Severity = classification.category == .blocked ? .error : .warning
                issues.append(
                    MigrationIssue(
                        severity: severity,
                        message: classification.reason,
                        detail: classification.reasons.count > 1
                            ? classification.reasons.dropFirst().joined(separator: ". ")
                            : nil,
                        dependency: podName
                    )
                )
            }
            
            entries.append(MigrationPlanEntry(
                podName: podName,
                currentVersion: dep.version,
                classification: classification.category,
                actions: actions,
                reasons: classification.reasons,
                targetName: targetName,
                packageCandidate: packageCandidate,
                declarations: dep.declarations,
                targetAttribution: attribution,
                targetSourceProfile: targetSourceProfile
            ))
        }
        
        let readinessScore = dependencies.isEmpty ? 0 : Int((Double(autoCount) / Double(dependencies.count)) * 100)
        return MigrationPlan(
            projectPath: projectPath,
            entries: entries,
            issues: issues,
            readinessScore: readinessScore,
            // The dictionary API cannot prove declaration- or lockfile-level
            // counts. Callers that own that source evidence may provide it;
            // otherwise omitting counts is safer than publishing false totals.
            counts: counts
        )
    }
    
    public func writePlan(_ plan: MigrationPlan, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(plan)
        
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        try data.write(to: url, options: .atomic)
    }
}
