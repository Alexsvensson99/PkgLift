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
            packageCandidate: entry.packageCandidate,
            declarations: entry.declarations,
            targetAttribution: entry.targetAttribution
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargets: ["App"]
        )) { error in
            XCTAssertEqual(error as? MigrationPlanPreflightError, .actionMismatch(dependency: "Alamofire"))
        }
    }

    func testAutoTargetAttributionMustAgreeWithLegacyTargetName() {
        let base = makeEntry()
        let entry = MigrationPlanEntry(
            podName: base.podName,
            currentVersion: base.currentVersion,
            classification: base.classification,
            actions: base.actions,
            targetName: base.targetName,
            packageCandidate: base.packageCandidate,
            declarations: base.declarations,
            targetAttribution: TargetAttribution(
                status: .multiple,
                targets: ["App", "Widget"],
                reason: "Multiple targets"
            )
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargets: ["App", "Widget"]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .actionMismatch(dependency: "Alamofire")
            )
        }
    }

    func testAutoRequiresLiteralDeclarationProvenance() {
        let base = makeEntry()
        let entry = MigrationPlanEntry(
            podName: base.podName,
            currentVersion: base.currentVersion,
            classification: base.classification,
            actions: base.actions,
            targetName: base.targetName,
            packageCandidate: base.packageCandidate,
            declarations: [],
            targetAttribution: base.targetAttribution
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargets: ["App"]
        )) { error in
            guard case .incompleteAutoEntry(_, let detail) = error as? MigrationPlanPreflightError else {
                return XCTFail("Expected incompleteAutoEntry, got \(error)")
            }
            XCTAssertTrue(detail.contains("provenance"))
            XCTAssertTrue(detail.contains("Regenerate"))
        }
    }

    func testAutoRejectsUnrepresentableDeclarationSource() {
        let base = makeEntry()
        let entry = MigrationPlanEntry(
            podName: base.podName,
            currentVersion: base.currentVersion,
            classification: base.classification,
            actions: base.actions,
            targetName: base.targetName,
            packageCandidate: base.packageCandidate,
            declarations: [
                PodfileDeclaration(
                    line: 3,
                    scope: .target,
                    scopeName: "App",
                    targetName: "App",
                    source: .unknown
                ),
            ],
            targetAttribution: base.targetAttribution
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargets: ["App"]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .actionMismatch(dependency: "Alamofire")
            )
        }
    }

    func testAutoRejectsDeclarationScopeThatCannotProveTarget() {
        let base = makeEntry()
        let entry = MigrationPlanEntry(
            podName: base.podName,
            currentVersion: base.currentVersion,
            classification: base.classification,
            actions: base.actions,
            targetName: base.targetName,
            packageCandidate: base.packageCandidate,
            declarations: [
                PodfileDeclaration(
                    line: 3,
                    scope: .topLevel,
                    targetName: "App",
                    source: .registry
                ),
            ],
            targetAttribution: base.targetAttribution
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargets: ["App"]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .actionMismatch(dependency: "Alamofire")
            )
        }
    }

    func testAdditivePlanFieldsRemainBackwardDecodableButLegacyAutoIsRefused() throws {
        let encoded = try JSONEncoder().encode(makePlan(entries: [makeEntry()]))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "counts")
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "declarations")
        entries[0].removeValue(forKey: "targetAttribution")
        object["entries"] = entries

        let oldShape = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MigrationPlan.self, from: oldShape)

        XCTAssertNil(decoded.counts)
        XCTAssertNil(decoded.entries[0].declarations)
        XCTAssertNil(decoded.entries[0].targetAttribution)
        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: decoded,
            availableTargets: ["App"]
        )) { error in
            guard case .incompleteAutoEntry(_, let detail) = error as? MigrationPlanPreflightError else {
                return XCTFail("Expected incompleteAutoEntry, got \(error)")
            }
            XCTAssertTrue(detail.contains("target-attribution"))
            XCTAssertTrue(detail.contains("Regenerate"))
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
            packageCandidate: package,
            declarations: [
                PodfileDeclaration(
                    line: 3,
                    scope: .target,
                    scopeName: targetName,
                    targetName: targetName,
                    source: .registry
                ),
            ],
            targetAttribution: TargetAttribution(
                status: .exact,
                targets: [targetName]
            )
        )
    }
}
