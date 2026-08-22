import Foundation
import PkgLiftCore

/// Fully validated operations derived from the typed actions in a migration plan.
public struct PreparedMigration: Sendable, Equatable {
    public struct PackageAddition: Sendable, Equatable {
        public let repositoryURL: String
        public let requirement: SwiftPMVersionRequirement

        public init(repositoryURL: String, requirement: SwiftPMVersionRequirement) {
            self.repositoryURL = repositoryURL
            self.requirement = requirement
        }
    }

    public struct ProductLink: Sendable, Equatable {
        public let dependency: String
        public let repositoryURL: String
        public let productName: String
        public let targetName: String

        public init(dependency: String, repositoryURL: String, productName: String, targetName: String) {
            self.dependency = dependency
            self.repositoryURL = repositoryURL
            self.productName = productName
            self.targetName = targetName
        }
    }

    public let podsToRemove: Set<String>
    public let packagesToAdd: [PackageAddition]
    public let productsToLink: [ProductLink]

    public init(
        podsToRemove: Set<String>,
        packagesToAdd: [PackageAddition],
        productsToLink: [ProductLink]
    ) {
        self.podsToRemove = podsToRemove
        self.packagesToAdd = packagesToAdd
        self.productsToLink = productsToLink
    }
}

public enum MigrationPlanPreflightError: LocalizedError, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case incompatiblePkgLiftVersion(String)
    case incompleteAutoEntry(dependency: String, detail: String)
    case actionMismatch(dependency: String)
    case targetNotFound(dependency: String, product: String, expectedTarget: String)
    case ambiguousTarget(dependency: String, product: String, expectedTarget: String, matchCount: Int)
    case conflictingRequirements(repositoryURL: String)
    case staleAutoEntry(dependency: String)
    case staleSourceProvenance(dependency: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Automatic migration refused: plan schema version \(version) is unsupported. Regenerate the plan with this PkgLift version."
        case .incompatiblePkgLiftVersion(let version):
            return "Automatic migration refused: the plan was produced by PkgLift \(version), but this executable is \(PkgLiftCore.pkgLiftVersion). Regenerate the plan."
        case .incompleteAutoEntry(let dependency, let detail):
            return "Automatic migration refused for '\(dependency)': \(detail) PkgLift will not invent missing migration data."
        case .actionMismatch(let dependency):
            return "Automatic migration refused for '\(dependency)': the typed plan actions or declaration evidence do not match the package, version, products, and target recorded in the plan. Regenerate the plan."
        case .targetNotFound(let dependency, let product, let expectedTarget):
            return "Automatic migration refused for '\(dependency)' product '\(product)': expected Xcode target '\(expectedTarget)' was not found. PkgLift will not choose another target."
        case .ambiguousTarget(let dependency, let product, let expectedTarget, let matchCount):
            return "Automatic migration refused for '\(dependency)' product '\(product)': target '\(expectedTarget)' matched \(matchCount) targets. PkgLift requires exactly one destination."
        case .conflictingRequirements(let repositoryURL):
            return "Automatic migration refused: package '\(repositoryURL)' has conflicting version requirements in the plan."
        case .staleAutoEntry(let dependency):
            return "Automatic migration refused for '\(dependency)': the saved plan no longer matches the current Podfile, lockfile, registry mapping, configuration, or target evidence. Regenerate the plan."
        case .staleSourceProvenance(let dependency):
            return "Automatic migration refused for '\(dependency)': external Git source provenance changed, is missing, or cannot be compared safely. Regenerate the plan before any mutation."
        }
    }
}

/// Validates the complete AUTO contract before any project file is mutated.
public struct MigrationPlanPreflight: Sendable {
    public init() {}

    /// Validates both the saved plan contract and a plan regenerated from the
    /// current project state before returning any executable operations.
    public func prepare(
        plan: MigrationPlan,
        currentPlan: MigrationPlan,
        availableTargetInfos: [TargetInfo]
    ) throws -> PreparedMigration {
        try validateSavedSourceProvenanceEntries(
            plan.entries,
            against: currentPlan.entries
        )
        let prepared = try prepareValidatedPlan(
            plan: plan,
            availableTargetInfos: availableTargetInfos
        )
        try validateSavedAutoEntries(
            plan.autoEntries,
            against: currentPlan.entries
        )
        return prepared
    }

    /// Backward-compatible target-name API. Names alone cannot prove source
    /// languages, so any AUTO entry is conservatively refused.
    public func prepare(
        plan: MigrationPlan,
        currentPlan: MigrationPlan,
        availableTargets: [String]
    ) throws -> PreparedMigration {
        try prepare(
            plan: plan,
            currentPlan: currentPlan,
            availableTargetInfos: availableTargets.map {
                TargetInfo(name: $0, type: "unknown")
            }
        )
    }

    /// A caller without a regenerated current plan cannot safely compare
    /// external source evidence, so this overload refuses any such snapshot.
    public func prepare(
        plan: MigrationPlan,
        availableTargetInfos: [TargetInfo]
    ) throws -> PreparedMigration {
        if let external = plan.entries.first(where: { $0.sourceProvenance != nil }) {
            throw MigrationPlanPreflightError.staleSourceProvenance(
                dependency: external.podName
            )
        }
        return try prepareValidatedPlan(
            plan: plan,
            availableTargetInfos: availableTargetInfos
        )
    }

    private func prepareValidatedPlan(
        plan: MigrationPlan,
        availableTargetInfos: [TargetInfo]
    ) throws -> PreparedMigration {
        guard plan.schemaVersion == MigrationPlan.schemaVersion else {
            throw MigrationPlanPreflightError.unsupportedSchemaVersion(plan.schemaVersion)
        }
        guard plan.pkgLiftVersion == PkgLiftCore.pkgLiftVersion else {
            throw MigrationPlanPreflightError.incompatiblePkgLiftVersion(plan.pkgLiftVersion)
        }
        var podsToRemove: Set<String> = []
        var packagesByIdentity: [String: PreparedMigration.PackageAddition] = [:]
        var packageOrder: [String] = []
        var productLinks: [PreparedMigration.ProductLink] = []

        for entry in plan.autoEntries {
            let dependency = entry.podName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dependency.isEmpty else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: entry.podName,
                    detail: "the dependency name is empty."
                )
            }
            guard entry.sourceProvenance == nil else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "external Git source provenance is analysis-only and cannot authorize AUTO migration."
                )
            }
            guard let package = entry.packageCandidate else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "the SwiftPM package mapping is missing."
                )
            }
            guard let requirement = package.versionRequirement else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "the SwiftPM version requirement is missing or ambiguous."
                )
            }
            let repositoryURL = package.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !repositoryURL.isEmpty else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "the SwiftPM repository URL is missing."
                )
            }
            guard !package.products.isEmpty,
                  package.products.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "the SwiftPM product list is missing or invalid."
                )
            }
            guard let supportedLanguages = package.supportedConsumerLanguages,
                  !supportedLanguages.isEmpty,
                  Set(supportedLanguages).count == supportedLanguages.count else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "verified SwiftPM consumer-language evidence is missing or invalid. Regenerate the plan."
                )
            }
            guard let targetName = entry.targetName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !targetName.isEmpty else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "the destination Xcode target is missing or ambiguous."
                )
            }
            guard let attribution = entry.targetAttribution else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "exact target-attribution evidence is missing. Regenerate the plan."
                )
            }
            guard attribution.status == .exact,
                  attribution.targets == [targetName],
                  attribution.unresolvedDeclarationCount == 0 else {
                throw MigrationPlanPreflightError.actionMismatch(dependency: dependency)
            }
            guard let declarations = entry.declarations, !declarations.isEmpty else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "literal Podfile declaration provenance is missing. Regenerate the plan."
                )
            }
            guard declarations.allSatisfy({ declaration in
                declaration.targetName == targetName
                    && declaration.isEligibleForAutomaticMigration
            }) else {
                throw MigrationPlanPreflightError.actionMismatch(dependency: dependency)
            }
            guard let targetSourceProfile = entry.targetSourceProfile else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "the destination target source-language profile is missing. Regenerate the plan."
                )
            }
            guard targetSourceProfile.completeness == .complete,
                  !targetSourceProfile.languages.isEmpty else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "the destination target source-language profile is incomplete or empty. Regenerate the plan."
                )
            }
            guard Set(targetSourceProfile.languages).isSubset(of: Set(supportedLanguages)) else {
                throw MigrationPlanPreflightError.actionMismatch(dependency: dependency)
            }

            var expectedActions: [MigrationAction] = [
                .removePod(name: dependency),
                .addSwiftPackage(repositoryURL: repositoryURL, requirement: requirement),
            ]
            expectedActions.append(contentsOf: package.products.map {
                .linkProduct(
                    repositoryURL: repositoryURL,
                    productName: $0,
                    targetName: targetName
                )
            })

            guard entry.actions == expectedActions else {
                throw MigrationPlanPreflightError.actionMismatch(dependency: dependency)
            }

            let matchingTargets = availableTargetInfos.filter { $0.name == targetName }
            guard let firstProduct = package.products.first else {
                throw MigrationPlanPreflightError.incompleteAutoEntry(
                    dependency: dependency,
                    detail: "the SwiftPM product list is missing or invalid."
                )
            }
            if matchingTargets.isEmpty {
                throw MigrationPlanPreflightError.targetNotFound(
                    dependency: dependency,
                    product: firstProduct,
                    expectedTarget: targetName
                )
            }
            if matchingTargets.count != 1 {
                throw MigrationPlanPreflightError.ambiguousTarget(
                    dependency: dependency,
                    product: firstProduct,
                    expectedTarget: targetName,
                    matchCount: matchingTargets.count
                )
            }
            guard matchingTargets[0].sourceProfile == targetSourceProfile else {
                throw MigrationPlanPreflightError.staleAutoEntry(dependency: dependency)
            }

            for product in package.products {
                productLinks.append(.init(
                    dependency: dependency,
                    repositoryURL: repositoryURL,
                    productName: product,
                    targetName: targetName
                ))
            }

            podsToRemove.insert(dependency)
            let identity = RepositoryIdentity.normalized(repositoryURL)
            let addition = PreparedMigration.PackageAddition(
                repositoryURL: repositoryURL,
                requirement: requirement
            )
            if let existing = packagesByIdentity[identity], existing.requirement != requirement {
                throw MigrationPlanPreflightError.conflictingRequirements(repositoryURL: repositoryURL)
            }
            if packagesByIdentity[identity] == nil {
                packagesByIdentity[identity] = addition
                packageOrder.append(identity)
            }
        }

        return PreparedMigration(
            podsToRemove: podsToRemove,
            packagesToAdd: packageOrder.compactMap { packagesByIdentity[$0] },
            productsToLink: productLinks
        )
    }

    /// Backward-compatible target-name API. It retains source compatibility
    /// while refusing AUTO because names do not contain language evidence.
    public func prepare(
        plan: MigrationPlan,
        availableTargets: [String]
    ) throws -> PreparedMigration {
        try prepare(
            plan: plan,
            availableTargetInfos: availableTargets.map {
                TargetInfo(name: $0, type: "unknown")
            }
        )
    }

    private func validateSavedAutoEntries(
        _ savedEntries: [MigrationPlanEntry],
        against currentEntries: [MigrationPlanEntry]
    ) throws {
        let currentByName = Dictionary(grouping: currentEntries, by: \.podName)
        var seenNames: Set<String> = []

        for saved in savedEntries {
            guard seenNames.insert(saved.podName).inserted,
                  let matches = currentByName[saved.podName],
                  matches.count == 1,
                  let current = matches.first,
                  current.classification == .auto,
                  current.currentVersion == saved.currentVersion,
                  current.actions == saved.actions,
                  current.targetName == saved.targetName,
                  current.packageCandidate == saved.packageCandidate,
                  current.sourceProvenance == saved.sourceProvenance,
                  current.declarations == saved.declarations,
                  current.targetAttribution == saved.targetAttribution,
                  current.targetSourceProfile == saved.targetSourceProfile else {
                throw MigrationPlanPreflightError.staleAutoEntry(
                    dependency: saved.podName
                )
            }
        }
    }

    /// External Git evidence is part of the plan snapshot even though v0.4
    /// never executes it. A changed external source can alter the remaining
    /// CocoaPods graph, so applying an otherwise unrelated AUTO entry must stop
    /// until the complete plan has been regenerated.
    private func validateSavedSourceProvenanceEntries(
        _ savedEntries: [MigrationPlanEntry],
        against currentEntries: [MigrationPlanEntry]
    ) throws {
        let savedExternal = Dictionary(grouping: savedEntries.filter {
            $0.sourceProvenance != nil
        }, by: \.podName)
        let currentExternal = Dictionary(grouping: currentEntries.filter {
            $0.sourceProvenance != nil
        }, by: \.podName)
        let names = Set(savedExternal.keys).union(currentExternal.keys).sorted()

        for name in names {
            guard let saved = savedExternal[name], saved.count == 1,
                  let current = currentExternal[name], current.count == 1,
                  isSafelyComparable(saved[0].sourceProvenance),
                  isSafelyComparable(current[0].sourceProvenance),
                  saved[0].sourceProvenance == current[0].sourceProvenance,
                  saved[0].currentVersion == current[0].currentVersion,
                  saved[0].targetName == current[0].targetName,
                  saved[0].declarations == current[0].declarations,
                  saved[0].targetAttribution == current[0].targetAttribution else {
                throw MigrationPlanPreflightError.staleSourceProvenance(
                    dependency: name
                )
            }
        }
    }

    /// Redacted or malformed evidence is deliberately lossy. Equality between
    /// two redaction markers cannot prove the underlying external source stayed
    /// unchanged, so applying unrelated AUTO entries must stop as well.
    private func isSafelyComparable(
        _ provenance: DependencySourceProvenance?
    ) -> Bool {
        guard case .git(let git)? = provenance else { return false }
        switch git.status {
        case .supportedImmutable, .mutable, .unpinned, .ambiguousRepository:
            return true
        case .credentialBearing, .incomplete, .conflicting, .unsupportedURL,
             .unsupportedSyntax:
            return false
        }
    }

}
