import XCTest
import PkgLiftCore
@testable import PkgLiftMigration

final class MigrationPlanPreflightTests: XCTestCase {
    func testPreferredTargetProducesPreparedTypedOperations() throws {
        let plan = makePlan(entries: [makeEntry()])

        let prepared = try MigrationPlanPreflight().prepare(
            plan: plan,
            availableTargetInfos: [targetInfo("App"), targetInfo("Widget")]
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

    func testDirectPreflightRejectsLegacyOrUnsafeHeaderEvidence() {
        let base = makeEntry()
        let basePackage = makePackage()
        let package = PackageCandidate(
            repositoryURL: basePackage.repositoryURL, products: basePackage.products,
            versionRequirement: basePackage.versionRequirement, confidence: .verified,
            supportedConsumerLanguages: [.swift, .objectiveC]
        )
        for status: TargetHeaderImportStatus? in [nil, .requiresReview, .incomplete] {
            let profile = TargetSourceProfile(
                languages: [.objectiveC], completeness: .complete, headerImports: status
            )
            let entry = MigrationPlanEntry(
                podName: base.podName, currentVersion: base.currentVersion,
                classification: .auto, actions: base.actions, targetName: base.targetName,
                packageCandidate: package, declarations: base.declarations,
                targetAttribution: base.targetAttribution, targetSourceProfile: profile
            )
            XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
                plan: makePlan(entries: [entry]),
                availableTargetInfos: [TargetInfo(name: "App", type: "application", sourceProfile: profile)]
            )) { error in
                guard case .incompleteAutoEntry(_, let detail) = error as? MigrationPlanPreflightError else {
                    return XCTFail("Expected header evidence refusal: \(error)")
                }
                XCTAssertTrue(detail.contains("header-import"))
            }
        }
    }

    func testMissingPreferredTargetIsRefused() {
        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [makeEntry(targetName: "Missing")]),
            availableTargetInfos: [targetInfo("App"), targetInfo("Widget")]
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
            availableTargetInfos: [targetInfo("App"), targetInfo("App")]
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
            availableTargetInfos: [targetInfo("OnlyTarget")]
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
            confidence: .verified,
            supportedConsumerLanguages: [.swift]
        )
        let entry = MigrationPlanEntry(
            podName: "Alamofire",
            classification: .auto,
            actions: [.removePod(name: "Alamofire")],
            targetName: "App",
            packageCandidate: package,
            targetSourceProfile: targetInfo("App").sourceProfile
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargetInfos: [targetInfo("App")]
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
            targetAttribution: entry.targetAttribution,
            targetSourceProfile: entry.targetSourceProfile
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargetInfos: [targetInfo("App")]
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
            ),
            targetSourceProfile: base.targetSourceProfile
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargetInfos: [targetInfo("App"), targetInfo("Widget")]
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
            targetAttribution: base.targetAttribution,
            targetSourceProfile: base.targetSourceProfile
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargetInfos: [targetInfo("App")]
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
            targetAttribution: base.targetAttribution,
            targetSourceProfile: base.targetSourceProfile
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargetInfos: [targetInfo("App")]
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
            targetAttribution: base.targetAttribution,
            targetSourceProfile: base.targetSourceProfile
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargetInfos: [targetInfo("App")]
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
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            guard case .incompleteAutoEntry(_, let detail) = error as? MigrationPlanPreflightError else {
                return XCTFail("Expected incompleteAutoEntry, got \(error)")
            }
            XCTAssertTrue(detail.contains("target-attribution"))
            XCTAssertTrue(detail.contains("Regenerate"))
        }
    }

    func testSchemaOnePlanWithoutLanguageEvidenceDecodesButIsRefused() throws {
        let encoded = try JSONEncoder().encode(makePlan(entries: [makeEntry()]))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "targetSourceProfile")
        var package = try XCTUnwrap(entries[0]["packageCandidate"] as? [String: Any])
        package.removeValue(forKey: "supportedConsumerLanguages")
        entries[0]["packageCandidate"] = package
        object["entries"] = entries

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MigrationPlan.self, from: legacyData)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertNil(decoded.entries[0].packageCandidate?.supportedConsumerLanguages)
        XCTAssertNil(decoded.entries[0].targetSourceProfile)
        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: decoded,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            guard case .incompleteAutoEntry(_, let detail) = error as? MigrationPlanPreflightError else {
                return XCTFail("Expected incompleteAutoEntry, got \(error)")
            }
            XCTAssertTrue(detail.contains("consumer-language"))
            XCTAssertTrue(detail.contains("Regenerate"))
        }
    }

    func testCurrentTargetLanguageProfileMustMatchSavedEvidence() {
        let plan = makePlan(entries: [makeEntry()])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: plan,
            availableTargetInfos: [targetInfo("App", languages: [.swift, .objectiveC])]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleAutoEntry(dependency: "Alamofire")
            )
        }
    }

    func testCurrentIncompleteTargetLanguageProfileRefusesSavedAutoEvidence() {
        let plan = makePlan(entries: [makeEntry()])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: plan,
            availableTargetInfos: [targetInfo("App", completeness: .incomplete)]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleAutoEntry(dependency: "Alamofire")
            )
        }
    }

    func testSavedAndRegeneratedLanguageEvidenceMustAgree() {
        let saved = makePlan(entries: [makeEntry()])
        let base = makeEntry()
        let changedEntry = MigrationPlanEntry(
            podName: base.podName,
            currentVersion: base.currentVersion,
            classification: base.classification,
            actions: base.actions,
            reasons: base.reasons,
            targetName: base.targetName,
            packageCandidate: base.packageCandidate,
            declarations: base.declarations,
            targetAttribution: base.targetAttribution,
            targetSourceProfile: TargetSourceProfile(
                languages: [.swift, .objectiveC],
                completeness: .complete
            )
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: saved,
            currentPlan: makePlan(entries: [changedEntry]),
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleAutoEntry(dependency: "Alamofire")
            )
        }
    }

    func testAutoEntryWithExternalSourceProvenanceIsRefused() {
        let entry = makeEntry(sourceProvenance: makeGitProvenance(branch: "main"))
        let plan = makePlan(entries: [entry])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: plan,
            currentPlan: plan,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            guard case .incompleteAutoEntry(_, let detail) = error as? MigrationPlanPreflightError else {
                return XCTFail("Expected incompleteAutoEntry, got \(error)")
            }
            XCTAssertTrue(detail.contains("analysis-only"))
            XCTAssertTrue(detail.contains("AUTO"))
        }
    }

    func testIdenticalExternalProvenanceAllowsUnrelatedAutoPreflight() throws {
        let external = makeExternalEntry(branch: "main")
        let plan = makePlan(entries: [makeEntry(), external])

        let prepared = try MigrationPlanPreflight().prepare(
            plan: plan,
            currentPlan: plan,
            availableTargetInfos: [targetInfo("App")]
        )

        XCTAssertEqual(prepared.podsToRemove, ["Alamofire"])
    }

    func testMatchedRegistrySourceAllowsRegeneratedPreflight() throws {
        let provenance = matchedRegistrySource()
        let entry = makeEntry(registrySourceProvenance: provenance)
        let plan = makePlan(entries: [entry])

        let prepared = try MigrationPlanPreflight().prepare(
            plan: plan,
            currentPlan: plan,
            availableTargetInfos: [targetInfo("App")]
        )
        XCTAssertEqual(prepared.podsToRemove, ["Alamofire"])
    }

    func testChangedRegistrySourceInvalidatesWholeSnapshot() {
        let saved = makePlan(entries: [makeEntry(registrySourceProvenance: matchedRegistrySource())])
        let current = makePlan(entries: [makeEntry()])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: saved,
            currentPlan: current,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleRegistrySourceProvenance(dependency: "Alamofire")
            )
        }
    }

    func testChangedRetainedRegistrySourceInvalidatesUnrelatedAutoEntry() {
        let auto = makeEntry(registrySourceProvenance: matchedRegistrySource())
        let saved = makePlan(entries: [auto, makeRetainedRegistryEntry(
            provenance: matchedRegistrySource()
        )])
        let current = makePlan(entries: [auto, makeRetainedRegistryEntry(
            provenance: RegistrySourceProvenance(
                declarations: [RegistrySourceDeclarationEvidence(
                    line: 1,
                    repository: .cocoaPodsSpecsGit
                )],
                lockfile: RegistrySourceLockfileEvidence(repositories: [.cocoaPodsTrunk])
            )
        )])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: saved,
            currentPlan: current,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleRegistrySourceProvenance(dependency: "RetainedKit")
            )
        }
    }

    func testRegistrySourceRequiresCurrentSnapshotThroughPublicAPI() {
        let plan = makePlan(entries: [
            makeEntry(registrySourceProvenance: matchedRegistrySource()),
        ])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: plan,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleRegistrySourceProvenance(dependency: "Alamofire")
            )
        }
    }

    func testSchemaOneDowngradeCannotCarryRegistrySourceEvidence() throws {
        let schemaTwo = makePlan(entries: [
            makeEntry(registrySourceProvenance: matchedRegistrySource()),
        ])
        XCTAssertEqual(schemaTwo.schemaVersion, 2)
        let downgraded = try replacingSchemaVersion(in: schemaTwo, with: 1)

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: downgraded,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .schemaEvidenceMismatch(schemaVersion: 1)
            )
        }
    }

    func testSchemaTwoWithoutRegistryEvidenceIsRefused() throws {
        let upgraded = try replacingSchemaVersion(
            in: makePlan(entries: [makeEntry()]),
            with: 2
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: upgraded,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .schemaEvidenceMismatch(schemaVersion: 2)
            )
        }
    }

    func testUnknownFuturePlanSchemaIsRefusedBeforeOtherChecks() throws {
        let future = try replacingSchemaVersion(
            in: makePlan(entries: [makeEntry(registrySourceProvenance: matchedRegistrySource())]),
            with: 99
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: future,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .unsupportedSchemaVersion(99)
            )
        }
        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: future,
            currentPlan: makePlan(entries: [makeEntry()]),
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .unsupportedSchemaVersion(99)
            )
        }
        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [makeEntry()]),
            currentPlan: future,
            availableTargets: ["App"]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .unsupportedSchemaVersion(99)
            )
        }
    }

    func testExternalProvenanceRequiresCurrentSnapshotThroughPublicAPI() {
        let plan = makePlan(entries: [
            makeEntry(),
            makeExternalEntry(branch: "main"),
        ])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: plan,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleSourceProvenance(dependency: "ExternalKit")
            )
        }
    }

    func testChangedExternalProvenanceInvalidatesWholeSavedSnapshot() {
        let saved = makePlan(entries: [makeEntry(), makeExternalEntry(branch: "main")])
        let current = makePlan(entries: [makeEntry(), makeExternalEntry(branch: "develop")])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: saved,
            currentPlan: current,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleSourceProvenance(dependency: "ExternalKit")
            )
            let description = error.localizedDescription
            XCTAssertFalse(description.contains("example.invalid"))
            XCTAssertFalse(description.contains("main"))
            XCTAssertFalse(description.contains("develop"))
        }
    }

    func testCaseDistinctExternalRepositoryPathInvalidatesWholeSavedSnapshot() {
        let saved = makePlan(entries: [
            makeEntry(),
            makeExternalEntry(
                branch: "main",
                repositoryURL: "https://example.invalid/Owner/ExternalKit.GIT"
            ),
        ])
        let current = makePlan(entries: [
            makeEntry(),
            makeExternalEntry(
                branch: "main",
                repositoryURL: "https://example.invalid/Owner/ExternalKit.git"
            ),
        ])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: saved,
            currentPlan: current,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleSourceProvenance(dependency: "ExternalKit")
            )
        }
    }

    func testMissingExternalProvenanceEntryInvalidatesWholeSavedSnapshot() {
        let saved = makePlan(entries: [makeEntry(), makeExternalEntry(branch: "main")])
        let current = makePlan(entries: [makeEntry()])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: saved,
            currentPlan: current,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleSourceProvenance(dependency: "ExternalKit")
            )
        }
    }

    func testChangedExternalDeclarationTargetInvalidatesWholeSavedSnapshot() {
        let saved = makePlan(entries: [
            makeEntry(),
            makeExternalEntry(branch: "main", targetName: "App"),
        ])
        let current = makePlan(entries: [
            makeEntry(),
            makeExternalEntry(branch: "main", targetName: "Widget"),
        ])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: saved,
            currentPlan: current,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleSourceProvenance(dependency: "ExternalKit")
            )
        }
    }

    func testLossyExternalEvidenceRefusesUnrelatedAutoPreflight() {
        let external = MigrationPlanEntry(
            podName: "ExternalKit",
            sourceProvenance: .git(.unsupportedSyntax),
            classification: .review,
            actions: [.manual(description: "Review external source")]
        )
        let plan = makePlan(entries: [makeEntry(), external])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: plan,
            currentPlan: plan,
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleSourceProvenance(dependency: "ExternalKit")
            )
            XCTAssertTrue(error.localizedDescription.contains("cannot be compared safely"))
        }
    }

    func testTargetNamesAloneCannotSatisfyLanguagePreflight() {
        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [makeEntry()]),
            availableTargets: ["App"]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleAutoEntry(dependency: "Alamofire")
            )
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
            availableTargetInfos: [targetInfo("App")]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .incompatiblePkgLiftVersion("0.1.1")
            )
        }
    }

    func testPlatformConstrainedEntryAcceptsMatchingDeploymentTarget() throws {
        let entry = makeEntry(packageCandidate: platformPackage())

        let prepared = try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [entry]),
            availableTargetInfos: [
                targetInfo("App", platform: "iOS", deploymentTarget: "15.0"),
            ]
        )

        XCTAssertEqual(prepared.podsToRemove, ["Alamofire"])
    }

    func testPlatformConstrainedEntryRefusesUnknownOtherAndLowerEnvironments() {
        let plan = makePlan(entries: [makeEntry(packageCandidate: platformPackage())])
        let cases: [(TargetInfo, MigrationPlanPreflightError)] = [
            (
                targetInfo("App", platform: nil, deploymentTarget: nil),
                .targetPlatformEvidenceMissing(dependency: "Alamofire")
            ),
            (
                targetInfo("App", platform: "macOS", deploymentTarget: "15.0"),
                .targetPlatformUnsupported(dependency: "Alamofire", platform: "macOS")
            ),
            (
                targetInfo("App", platform: "iOS", deploymentTarget: nil),
                .targetDeploymentTargetEvidenceMissing(dependency: "Alamofire")
            ),
            (
                targetInfo("App", platform: "iOS", deploymentTarget: "15.x"),
                .targetDeploymentTargetInvalid(dependency: "Alamofire", value: "15.x")
            ),
            (
                targetInfo("App", platform: "iOS", deploymentTarget: "14.9"),
                .targetDeploymentTargetUnsupported(
                    dependency: "Alamofire",
                    actual: "14.9",
                    minimum: "15.0"
                )
            ),
        ]

        for (target, expectedError) in cases {
            XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
                plan: plan,
                availableTargetInfos: [target]
            )) { error in
                XCTAssertEqual(error as? MigrationPlanPreflightError, expectedError)
            }
        }
    }

    func testInvalidSavedPlatformEvidenceIsRefused() {
        let package = PackageCandidate(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            products: ["Alamofire"],
            versionRequirement: .exact("5.0.0"),
            confidence: .verified,
            supportedConsumerLanguages: [.swift],
            supportedConsumerPlatforms: []
        )

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: makePlan(entries: [makeEntry(packageCandidate: package)]),
            availableTargetInfos: [
                targetInfo("App", platform: "iOS", deploymentTarget: "15.0"),
            ]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .invalidConsumerPlatformEvidence(dependency: "Alamofire")
            )
        }
    }

    func testAddedPlatformConstraintMakesSavedAutoEntryStale() {
        let saved = makePlan(entries: [makeEntry()])
        let current = makePlan(entries: [makeEntry(packageCandidate: platformPackage())])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: saved,
            currentPlan: current,
            availableTargetInfos: [
                targetInfo("App", platform: "iOS", deploymentTarget: "15.0"),
            ]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleAutoEntry(dependency: "Alamofire")
            )
        }
    }

    func testRemovedPlatformConstraintMakesSavedAutoEntryStale() {
        let saved = makePlan(entries: [makeEntry(packageCandidate: platformPackage())])
        let current = makePlan(entries: [makeEntry()])

        XCTAssertThrowsError(try MigrationPlanPreflight().prepare(
            plan: saved,
            currentPlan: current,
            availableTargetInfos: [
                targetInfo("App", platform: "iOS", deploymentTarget: "15.0"),
            ]
        )) { error in
            XCTAssertEqual(
                error as? MigrationPlanPreflightError,
                .staleAutoEntry(dependency: "Alamofire")
            )
        }
    }

    func testLegacyPackageCandidateOmitsPlatformFieldFromJSON() throws {
        let data = try JSONEncoder().encode(makePackage())
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNil(object["supportedConsumerPlatforms"])
    }

    func testPlatformConstraintRoundTripsInPlanJSON() throws {
        let plan = makePlan(entries: [makeEntry(packageCandidate: platformPackage())])

        let decoded = try JSONDecoder().decode(
            MigrationPlan.self,
            from: JSONEncoder().encode(plan)
        )

        XCTAssertEqual(
            decoded.entries[0].packageCandidate?.supportedConsumerPlatforms,
            [SupportedConsumerPlatform(platform: .iOS, minimumDeploymentTarget: "15.0")]
        )
    }

    private func makePlan(entries: [MigrationPlanEntry]) -> MigrationPlan {
        MigrationPlan(projectPath: "/tmp/App.xcodeproj", entries: entries, issues: [], readinessScore: 100)
    }

    private func makePackage() -> PackageCandidate {
        PackageCandidate(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            products: ["Alamofire"],
            versionRequirement: .exact("5.0.0"),
            confidence: .verified,
            supportedConsumerLanguages: [.swift]
        )
    }

    private func platformPackage() -> PackageCandidate {
        PackageCandidate(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            products: ["Alamofire"],
            versionRequirement: .exact("5.0.0"),
            confidence: .verified,
            supportedConsumerLanguages: [.swift],
            supportedConsumerPlatforms: [
                SupportedConsumerPlatform(platform: .iOS, minimumDeploymentTarget: "15.0"),
            ]
        )
    }

    private func targetInfo(
        _ name: String,
        languages: [SourceLanguage] = [.swift],
        completeness: SourceProfileCompleteness = .complete,
        platform: String? = nil,
        deploymentTarget: String? = nil
    ) -> TargetInfo {
        TargetInfo(
            name: name,
            type: "application",
            platform: platform,
            deploymentTarget: deploymentTarget,
            sourceProfile: TargetSourceProfile(
                languages: languages,
                completeness: completeness
            )
        )
    }

    private func makeEntry(
        targetName: String = "App",
        sourceProvenance: DependencySourceProvenance? = nil,
        registrySourceProvenance: RegistrySourceProvenance? = nil,
        packageCandidate: PackageCandidate? = nil
    ) -> MigrationPlanEntry {
        let package = packageCandidate ?? makePackage()
        return MigrationPlanEntry(
            podName: "Alamofire",
            currentVersion: "5.0.0",
            sourceProvenance: sourceProvenance,
            registrySourceProvenance: registrySourceProvenance,
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
            ),
            targetSourceProfile: targetInfo(targetName).sourceProfile
        )
    }

    private func makeExternalEntry(
        branch: String,
        targetName: String? = nil,
        repositoryURL: String = "https://example.invalid/Owner/ExternalKit.git"
    ) -> MigrationPlanEntry {
        let declarations = targetName.map { target in
            [PodfileDeclaration(
                line: 3,
                scope: .target,
                scopeName: target,
                targetName: target,
                source: .git(
                    url: "https://example.invalid/Owner/ExternalKit",
                    ref: .branch(branch)
                )
            )]
        }
        let attribution = targetName.map { target in
            TargetAttribution(status: .exact, targets: [target])
        }
        return MigrationPlanEntry(
            podName: "ExternalKit",
            currentVersion: "1.0.0",
            sourceProvenance: makeGitProvenance(
                branch: branch,
                repositoryURL: repositoryURL
            ),
            classification: .review,
            actions: [.manual(description: "Review external source")],
            targetName: targetName,
            declarations: declarations,
            targetAttribution: attribution
        )
    }

    private func makeRetainedRegistryEntry(
        provenance: RegistrySourceProvenance
    ) -> MigrationPlanEntry {
        MigrationPlanEntry(
            podName: "RetainedKit",
            currentVersion: "1.0.0",
            registrySourceProvenance: provenance,
            classification: .review,
            actions: [.manual(description: "Keep on CocoaPods")],
            declarations: [
                PodfileDeclaration(
                    line: 6,
                    scope: .target,
                    scopeName: "App",
                    targetName: "App",
                    source: .registry
                ),
            ],
            targetAttribution: TargetAttribution(status: .exact, targets: ["App"])
        )
    }

    private func makeGitProvenance(
        branch: String,
        repositoryURL: String = "https://example.invalid/Owner/ExternalKit.git"
    ) -> DependencySourceProvenance {
        let repository = GitRepositoryCanonicalizer.evidence(
            for: repositoryURL
        )
        let reference = GitReferenceEvidence.make(kind: .branch, value: branch) ?? .unpinned
        return .git(GitSourceProvenance(declarations: [
            GitDeclarationEvidence(repository: repository, reference: reference),
        ]))
    }

    private func matchedRegistrySource() -> RegistrySourceProvenance {
        RegistrySourceProvenance(
            declarations: [
                RegistrySourceDeclarationEvidence(line: 1, repository: .cocoaPodsSpecsGit),
            ],
            lockfile: RegistrySourceLockfileEvidence(repositories: [.cocoaPodsSpecsGit])
        )
    }

    private func replacingSchemaVersion(
        in plan: MigrationPlan,
        with schemaVersion: Int
    ) throws -> MigrationPlan {
        let data = try JSONEncoder().encode(plan)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["schemaVersion"] = schemaVersion
        return try JSONDecoder().decode(
            MigrationPlan.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}
