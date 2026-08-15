import XCTest
import PkgLiftCore
@testable import PkgLiftMigration

final class MigrationPlanPreflightTests: XCTestCase {
    func testPreferredTargetProducesPreparedTypedOperations() throws {
        let plan = makePlan(entries: [makeEntry()])

        let prepared = try MigrationPlanPreflight().prepare(
            plan: plan,
            availableTargets: ["App", "Widget"]
        )

        XCTAssertEqual(prepared.podsToRemove, ["Alamofire"])
        XCTAssertEqual(prepared.packagesToAdd, [
            .init(
                repositoryURL: "https://github.com/Alamofire/Alamofire",
                requirement: .exact("5.0.0")
            )
        ])
        XCTAssertEqual(prepared.productsToLink, [
            .init(
                dependency: "Alamofire",
                repositoryURL: "https://github.com/Alamofire/Alamofire",
                productName: "Alamofire",
                targetName: "App"
            )
        ])
    }

    func testMissingPreferredTargetIsRefused() {
        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [makeEntry(targetName: "Missing")]),
            availableTargets: ["App", "Widget"]
        )) { error in
            XCTAssertEqual(error as? MigrationPlanPreflightError, .targetNotFound(
                dependency: "Alamofire",
                product: "Alamofire",
                expectedTarget: "Missing"
            ))
        }
    }

    func testDuplicateMatchingTargetsAreRefusedAsAmbiguous() {
        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [makeEntry()]),
            availableTargets: ["App", "App"]
        )) { error in
            XCTAssertEqual(error as? MigrationPlanPreflightError, .ambiguousTarget(
                dependency: "Alamofire",
                product: "Alamofire",
                expectedTarget: "App",
                matchCount: 2
            ))
        }
    }

    func testNoRecordedTargetNeverFallsBackToOnlyAvailableTarget() {
        let entry = MigrationPlanEntry(
            podName: "Alamofire",
            currentVersion: "5.0.0",
            classification: .auto,
            actions: [],
            targetName: nil,
            packageCandidate: makePackage()
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargets: ["OnlyTarget"]
        )) { error in
            guard case .incompleteAutoEntry(_, let detail) = error as? MigrationPlanPreflightError else {
                return XCTFail("Expected incompleteAutoEntry, got \(error)")
            }
            XCTAssertTrue(detail.contains("target"))
        }
    }

    func testMissingVersionIsRefusedWithoutSyntheticFallback() {
        let package = PackageCandidate(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            products: ["Alamofire"],
            versionRequirement: nil,
            confidence: .verified
        )
        let entry = MigrationPlanEntry(
            podName: "Alamofire",
            classification: .auto,
            actions: [.removePod(name: "Alamofire")],
            targetName: "App",
            packageCandidate: package
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargets: ["App"]
        )) { error in
            guard case .incompleteAutoEntry(_, let detail) = error as? MigrationPlanPreflightError else {
                return XCTFail("Expected incompleteAutoEntry, got \(error)")
            }
            XCTAssertTrue(detail.contains("version"))
            XCTAssertFalse(error.localizedDescription.contains("0.0.0"))
        }
    }

    func testPlanMetadataAndTypedActionsMustAgree() {
        var entry = makeEntry()
        entry = MigrationPlanEntry(
            podName: entry.podName,
            currentVersion: entry.currentVersion,
            classification: entry.classification,
            actions: [.removePod(name: "DifferentPod")],
            targetName: entry.targetName,
            packageCandidate: entry.packageCandidate
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargets: ["App"]
        )) { error in
            XCTAssertEqual(error as? MigrationPlanPreflightError, .actionMismatch(dependency: "Alamofire"))
        }
    }

    func testPlanProducedByVersion011IsRefusedByVersion012() throws {
        let encoded = try JSONEncoder().encode(makePlan(entries: [makeEntry()]))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["pkgLiftVersion"] = "0.1.1"
        let staleData = try JSONSerialization.data(withJSONObject: object)
        let stalePlan = try JSONDecoder().decode(MigrationPlan.self, from: staleData)

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: stalePlan,
            availableTargets: ["App"]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .incompatiblePkgLiftVersion("0.1.1")
            )
        }
    }

    private func makePlan(entries: [MigrationPlanEntry]) -> MigrationPlan {
        MigrationPlan(projectPath: "/tmp/App.xcodeproj", entries: entries, issues: [], readinessScore: 100)
    }

    private func makePackage() -> PackageCandidate {
        PackageCandidate(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            products: ["Alamofire"],
            versionRequirement: .exact("5.0.0"),
            confidence: .verified
        )
    }

    private func makeEntry(targetName: String = "App") -> MigrationPlanEntry {
        let package = makePackage()
        return MigrationPlanEntry(
            podName: "Alamofire",
            currentVersion: "5.0.0",
            classification: .auto,
            actions: [
                .removePod(name: "Alamofire"),
                .addSwiftPackage(
                    repositoryURL: package.repositoryURL,
                    requirement: .exact("5.0.0")
                ),
                .linkProduct(
                    repositoryURL: package.repositoryURL,
                    productName: "Alamofire",
                    targetName: targetName
                ),
            ],
            targetName: targetName,
            packageCandidate: package
        )
    }
}
