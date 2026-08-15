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
        }
    }
}

/// Validates the complete AUTO contract before any project file is mutated.
public struct MigrationPlanPreflight: Sendable {
    public init() {}

    public func prepare(plan: MigrationPlan, availableTargets: [String]) throws -> PreparedMigration {
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

            for product in package.products {
                let matches = availableTargets.filter { $0 == targetName }.count
                if matches == 0 {
                    throw MigrationPlanPreflightError.targetNotFound(
                        dependency: dependency,
                        product: product,
                        expectedTarget: targetName
                    )
                }
                if matches != 1 {
                    throw MigrationPlanPreflightError.ambiguousTarget(
                        dependency: dependency,
                        product: product,
                        expectedTarget: targetName,
                        matchCount: matches
                    )
                }
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

}
