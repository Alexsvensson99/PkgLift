//
//  MigrationPlannerTests.swift
//  PkgLiftMigrationTests
//

import XCTest
@testable import PkgLiftMigration
import PkgLiftCore

final class MigrationPlannerTests: XCTestCase {
    func testGeneratePlan() {
        let planner = MigrationPlanner()
        
        let dependencies = [
            "Alamofire": CocoaPodDependency(
                name: "Alamofire",
                version: "5.0.0",
                source: .registry,
                isDirect: true,
                targets: ["App"],
                declarations: [
                    PodfileDeclaration(
                        line: 1,
                        scope: .target,
                        scopeName: "App",
                        targetName: "App",
                        source: .registry
                    ),
                ],
                targetAttribution: TargetAttribution(status: .exact, targets: ["App"])
            )
        ]
        let mappings = [
            "Alamofire": RegistryMapping(
                pod: PodIdentifier(name: "Alamofire"),
                swiftpm: SwiftPMPackageInfo(
                    repository: "https://github.com/Alamofire/Alamofire",
                    products: ["Alamofire"],
                    minimumVersion: "5.0.0"
                ),
                migration: MigrationInfo(confidence: .verified)
            )
        ]
        let plan = planner.generatePlan(
            dependencies: dependencies,
            mappings: mappings,
            availableTargets: ["App"]
        )
        
        XCTAssertEqual(plan.entries.count, 1)
        XCTAssertEqual(plan.entries[0].podName, "Alamofire")
        XCTAssertEqual(plan.entries[0].classification, .auto)
        XCTAssertEqual(plan.entries[0].actions, [
            .removePod(name: "Alamofire"),
            .addSwiftPackage(
                repositoryURL: "https://github.com/Alamofire/Alamofire",
                requirement: .exact("5.0.0")
            ),
            .linkProduct(
                repositoryURL: "https://github.com/Alamofire/Alamofire",
                productName: "Alamofire",
                targetName: "App"
            ),
        ])
        XCTAssertNil(plan.counts)
    }

    func testGeneratePlanPreservesExplicitSourceCounts() {
        let counts = DependencyCounts(
            literalPodfileDeclarationCount: 3,
            uniqueDirectDependencyCount: 1,
            uniqueLockfileDependencyCount: 2,
            planEntryCount: 1,
            analysisCandidateCount: 2
        )

        let plan = MigrationPlanner().generatePlan(
            dependencies: [
                "Repeated": CocoaPodDependency(
                    name: "Repeated",
                    version: "1.0.0",
                    targets: ["App"]
                ),
            ],
            mappings: [:],
            counts: counts
        )

        XCTAssertEqual(plan.counts, counts)
    }

    func testLegacyTargetArrayCannotProduceAutoActions() {
        let dependency = CocoaPodDependency(
            name: "Alamofire",
            version: "5.0.0",
            targets: ["App"]
        )
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire",
                products: ["Alamofire"],
                minimumVersion: "5.0.0"
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        let entry = MigrationPlanner().generatePlan(
            dependencies: ["Alamofire": dependency],
            mappings: ["Alamofire": mapping],
            availableTargets: ["App"]
        ).entries[0]

        XCTAssertEqual(entry.classification, .review)
        XCTAssertTrue(entry.actions.isEmpty)
        XCTAssertTrue(entry.reasons.contains(
            "Literal Podfile declaration provenance is missing or inconsistent"
        ))
    }

    func testMissingVersionCannotProduceAutoActions() {
        let dependency = CocoaPodDependency(name: "Alamofire", targets: ["App"])
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire",
                products: ["Alamofire"],
                minimumVersion: "5.0.0"
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        let entry = MigrationPlanner().generatePlan(
            dependencies: ["Alamofire": dependency],
            mappings: ["Alamofire": mapping],
            availableTargets: ["App"]
        ).entries[0]

        XCTAssertEqual(entry.classification, .review)
        XCTAssertTrue(entry.actions.isEmpty)
        XCTAssertNil(entry.packageCandidate?.versionRequirement)
    }

    func testMultiplePodfileTargetsCannotProduceAutoActions() {
        let dependency = CocoaPodDependency(
            name: "Alamofire",
            version: "5.0.0",
            targets: ["App", "Widget"]
        )
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire",
                products: ["Alamofire"],
                minimumVersion: "5.0.0"
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        let entry = MigrationPlanner().generatePlan(
            dependencies: ["Alamofire": dependency],
            mappings: ["Alamofire": mapping],
            availableTargets: ["App", "Widget"]
        ).entries[0]

        XCTAssertEqual(entry.classification, .review)
        XCTAssertNil(entry.targetName)
        XCTAssertTrue(entry.actions.isEmpty)
    }

    func testMissingXcodeTargetCannotProduceAutoActions() {
        let dependency = CocoaPodDependency(
            name: "Alamofire",
            version: "5.0.0",
            targets: ["MissingApp"]
        )
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire",
                products: ["Alamofire"],
                minimumVersion: "5.0.0"
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        let entry = MigrationPlanner().generatePlan(
            dependencies: ["Alamofire": dependency],
            mappings: ["Alamofire": mapping],
            availableTargets: ["App"]
        ).entries[0]

        XCTAssertEqual(entry.classification, .review)
        XCTAssertTrue(entry.actions.isEmpty)
    }
}
