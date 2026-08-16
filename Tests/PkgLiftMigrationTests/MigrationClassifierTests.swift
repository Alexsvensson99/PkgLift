//
//  MigrationClassifierTests.swift
//  PkgLiftMigrationTests
//

import XCTest
@testable import PkgLiftMigration
import PkgLiftCore

final class MigrationClassifierTests: XCTestCase {
    func testAutoClassification() {
        let classifier = MigrationClassifier()
        let dependency = CocoaPodDependency(
            name: "Alamofire",
            version: "1.2.3",
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
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire.git",
                products: ["Alamofire"],
                minimumVersion: "1.0.0",
                supportedConsumerLanguages: [.swift]
            ),
            migration: MigrationInfo(confidence: .verified)
        )
        
        let result = classifier.classify(
            dependency: dependency,
            mapping: mapping,
            targetSourceProfile: swiftProfile,
            podfileFeatures: PodfileFeatures()
        )
        XCTAssertEqual(result.category, .auto)
    }
    
    func testUnknownWhenNoMapping() {
        let classifier = MigrationClassifier()
        let dependency = CocoaPodDependency(
            name: "Alamofire",
            version: "1.2.3",
            source: .registry,
            isDirect: true,
            targets: ["App"]
        )
        
        let result = classifier.classify(
            dependency: dependency,
            mapping: nil,
            podfileFeatures: PodfileFeatures()
        )
        XCTAssertEqual(result.category, .unknown)
    }
    
    func testReviewWhenHooksPresent() {
        let classifier = MigrationClassifier()
        var features = PodfileFeatures()
        features.hasPreInstallHook = true

        let dependency = CocoaPodDependency(
            name: "Alamofire",
            version: "1.2.3",
            source: .registry,
            isDirect: true,
            targets: ["App"]
        )
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire.git",
                products: ["Alamofire"],
                minimumVersion: "1.0.0",
                supportedConsumerLanguages: [.swift]
            ),
            migration: MigrationInfo(confidence: .verified)
        )
        
        let result = classifier.classify(
            dependency: dependency,
            mapping: mapping,
            targetSourceProfile: swiftProfile,
            podfileFeatures: features
        )
        XCTAssertEqual(result.category, .review)
    }

    func testReviewWhenMultipleTargetsArePlausible() {
        let dependency = CocoaPodDependency(
            name: "Alamofire",
            version: "1.2.3",
            targets: ["App", "Widget"]
        )
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire.git",
                products: ["Alamofire"],
                minimumVersion: "1.0.0",
                supportedConsumerLanguages: [.swift]
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        let result = MigrationClassifier().classify(dependency: dependency, mapping: mapping)
        XCTAssertEqual(result.category, .review)
    }

    func testReviewWhenVersionIsMissing() {
        let dependency = CocoaPodDependency(name: "Alamofire", targets: ["App"])
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire.git",
                products: ["Alamofire"],
                minimumVersion: "1.0.0",
                supportedConsumerLanguages: [.swift]
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        let result = MigrationClassifier().classify(dependency: dependency, mapping: mapping)
        XCTAssertEqual(result.category, .review)
    }

    func testLegacyTargetArrayCannotBecomeAutoWithoutProvenance() {
        let dependency = CocoaPodDependency(
            name: "SDWebImage",
            version: "5.18.1",
            targets: ["App"]
        )

        let result = MigrationClassifier().classify(
            dependency: dependency,
            mapping: makeMapping(minimumVersion: "5.1.0")
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reasons.contains(
            "Literal Podfile declaration provenance is missing or inconsistent"
        ))
        XCTAssertEqual(dependency.effectiveTargetAttribution.status, .partial)
    }

    func testTopLevelDeclarationCannotForgeExactTargetProvenance() {
        let dependency = CocoaPodDependency(
            name: "SDWebImage",
            version: "5.18.1",
            targets: ["App"],
            declarations: [
                PodfileDeclaration(
                    line: 1,
                    scope: .topLevel,
                    targetName: "App",
                    source: .registry
                ),
            ],
            targetAttribution: TargetAttribution(status: .exact, targets: ["App"])
        )

        let result = MigrationClassifier().classify(
            dependency: dependency,
            mapping: makeMapping(minimumVersion: "5.1.0")
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reasons.contains(
            "Literal Podfile declaration provenance is missing or inconsistent"
        ))
    }

    func testExternalSourceNeverBecomesAutoFromNameMatch() {
        let dependency = CocoaPodDependency(
            name: "Alamofire",
            version: "1.2.3",
            source: .git(url: "https://example.com/fork.git", ref: nil),
            targets: ["App"]
        )
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire.git",
                products: ["Alamofire"],
                minimumVersion: "1.0.0",
                supportedConsumerLanguages: [.swift]
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        let result = MigrationClassifier().classify(dependency: dependency, mapping: mapping)
        XCTAssertEqual(result.category, .review)
    }

    func testUnrepresentablePodfileDeclarationIsReviewWithExplicitReason() {
        let dependency = CocoaPodDependency(
            name: "SDWebImage",
            version: "5.18.1",
            source: .unknown,
            targets: ["App"]
        )

        let result = MigrationClassifier().classify(
            dependency: dependency,
            mapping: makeMapping(minimumVersion: "5.1.0")
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reasons.contains(
            "Podfile declaration source, options, or expressions cannot be represented safely"
        ))
        XCTAssertFalse(result.reasons.contains("External dependency source requires manual review"))
    }

    func testTransitiveDependencyNeverBecomesAuto() {
        let dependency = CocoaPodDependency(
            name: "Alamofire",
            version: "1.2.3",
            isDirect: false,
            targets: ["App"]
        )
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire.git",
                products: ["Alamofire"],
                minimumVersion: "1.0.0",
                supportedConsumerLanguages: [.swift]
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        XCTAssertEqual(
            MigrationClassifier().classify(
                dependency: dependency,
                mapping: mapping,
                targetSourceProfile: swiftProfile
            ).category,
            .review
        )
    }

    func testMissingMinimumVersionIsReviewOnly() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.1.0"),
            mapping: makeMapping(minimumVersion: nil),
            targetSourceProfile: swiftProfile
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reason.contains("no verified minimum"))
    }

    func testVersionBelowMinimumIsReview() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.0.6"),
            mapping: makeMapping(minimumVersion: "5.1.0"),
            targetSourceProfile: swiftProfile
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reason.contains("predates"))
    }

    func testVersionEqualToMinimumIsAuto() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.1.0"),
            mapping: makeMapping(minimumVersion: "5.1.0"),
            targetSourceProfile: swiftProfile
        )

        XCTAssertEqual(result.category, .auto)
        XCTAssertTrue(result.reason.contains("meets minimum"))
    }

    func testVersionAboveMinimumIsAuto() {
        XCTAssertEqual(
            MigrationClassifier().classify(
                dependency: makeDependency(version: "5.18.1"),
                mapping: makeMapping(minimumVersion: "5.1.0"),
                targetSourceProfile: swiftProfile
            ).category,
            .auto
        )
    }

    func testInvalidMinimumVersionIsReview() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.18.1"),
            mapping: makeMapping(minimumVersion: "5.1"),
            targetSourceProfile: swiftProfile
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reason.contains("minimum SwiftPM version is invalid"))
    }

    func testNonStableResolvedVersionIsReview() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.1.0-beta.1"),
            mapping: makeMapping(minimumVersion: "5.1.0"),
            targetSourceProfile: swiftProfile
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reason.contains("stable major.minor.patch"))
    }

    func testMismatchedMappingIdentifierIsReview() {
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "SDWebImage"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/SDWebImage/SDWebImage",
                products: ["SDWebImage"],
                minimumVersion: "5.1.0",
                supportedConsumerLanguages: [.swift, .objectiveC]
            ),
            migration: MigrationInfo(confidence: .verified)
        )
        let result = MigrationClassifier().classify(
            dependency: makeDependency(name: "SDWebImage/Core", version: "5.18.1"),
            mapping: mapping
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reason.contains("does not exactly match"))
    }

    func testAllMigrationAffectingPodfileFeaturesAreReview() {
        let cases: [(String, (inout PodfileFeatures) -> Void)] = [
            ("pre_install", { $0.hasPreInstallHook = true }),
            ("post_install", { $0.hasPostInstallHook = true }),
            ("script_phase", { $0.hasScriptPhase = true }),
            ("dynamic Ruby", { $0.hasDynamicRuby = true }),
            ("use_frameworks!", { $0.useFrameworks = true }),
            ("inherit! :search_paths", { $0.hasInheritSearchPaths = true }),
            ("abstract_target", { $0.hasAbstractTargets = true }),
        ]

        for (label, configure) in cases {
            var features = PodfileFeatures()
            configure(&features)
            let result = MigrationClassifier().classify(
                dependency: makeDependency(version: "5.18.1"),
                mapping: makeMapping(minimumVersion: "5.1.0"),
                targetSourceProfile: swiftProfile,
                podfileFeatures: features
            )
            XCTAssertEqual(result.category, .review, "Expected \(label) to block AUTO")
        }
    }

    func testReportsEveryRelevantSafetyReasonWithoutChangingBlockedClassification() {
        var features = PodfileFeatures()
        features.hasPostInstallHook = true
        features.hasDynamicRuby = true
        features.hasInheritSearchPaths = true
        let dependency = CocoaPodDependency(
            name: "ExternalKit",
            version: "1.2.3",
            source: .git(url: "https://example.invalid/ExternalKit.git", ref: nil),
            targets: [],
            targetAttribution: TargetAttribution(
                status: .unresolved,
                unresolvedDeclarationCount: 1,
                reason: "Declaration originates in a Ruby helper; call-site target is unresolved."
            )
        )

        let result = MigrationClassifier().classify(
            dependency: dependency,
            mapping: nil,
            podfileFeatures: features
        )

        XCTAssertEqual(result.category, .blocked)
        XCTAssertEqual(result.reason, "External source without mapping")
        XCTAssertEqual(result.reasons, [
            "External source without mapping",
            "No registry mapping",
            "Podfile install hook detected",
            "Dynamic Podfile logic detected",
            "inherit! :search_paths detected",
            "Declaration originates in a Ruby helper; call-site target is unresolved.",
        ])
    }

    func testMissingConsumerLanguageMetadataIsReview() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.18.1"),
            mapping: makeMapping(
                minimumVersion: "5.1.0",
                supportedLanguages: nil
            ),
            targetSourceProfile: swiftProfile
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reasons.contains(
            "Registry mapping has no verified consumer-language support"
        ))
    }

    func testIncompleteAndEmptyTargetProfilesAreReview() {
        let profiles = [
            TargetSourceProfile(languages: [.swift], completeness: .incomplete),
            TargetSourceProfile(languages: [], completeness: .complete),
        ]

        for profile in profiles {
            let result = MigrationClassifier().classify(
                dependency: makeDependency(version: "5.18.1"),
                mapping: makeMapping(minimumVersion: "5.1.0"),
                targetSourceProfile: profile
            )
            XCTAssertEqual(result.category, .review)
        }
    }

    func testMixedTargetRequiresExplicitSupportForBothLanguages() {
        let mixedProfile = TargetSourceProfile(
            languages: [.swift, .objectiveC],
            completeness: .complete
        )
        let swiftOnly = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.18.1"),
            mapping: makeMapping(
                minimumVersion: "5.1.0",
                supportedLanguages: [.swift]
            ),
            targetSourceProfile: mixedProfile
        )
        let mixedSupported = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.18.1"),
            mapping: makeMapping(minimumVersion: "5.1.0"),
            targetSourceProfile: mixedProfile
        )

        XCTAssertEqual(swiftOnly.category, .review)
        XCTAssertTrue(swiftOnly.reasons.contains { $0.contains("objectiveC") })
        XCTAssertEqual(mixedSupported.category, .auto)
    }

    func testCFamilyLanguageWithoutExplicitSupportIsReview() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.18.1"),
            mapping: makeMapping(minimumVersion: "5.1.0"),
            targetSourceProfile: TargetSourceProfile(
                languages: [.cPlusPlus],
                completeness: .complete
            )
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reasons.contains { $0.contains("cPlusPlus") })
    }

    private func makeDependency(
        name: String = "SDWebImage",
        version: String
    ) -> CocoaPodDependency {
        CocoaPodDependency(
            name: name,
            version: version,
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
    }

    private var swiftProfile: TargetSourceProfile {
        TargetSourceProfile(languages: [.swift], completeness: .complete)
    }

    private func makeMapping(
        minimumVersion: String?,
        supportedLanguages: [SourceLanguage]? = [.swift, .objectiveC]
    ) -> RegistryMapping {
        RegistryMapping(
            pod: PodIdentifier(name: "SDWebImage"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/SDWebImage/SDWebImage",
                products: ["SDWebImage"],
                minimumVersion: minimumVersion,
                supportedConsumerLanguages: supportedLanguages
            ),
            migration: MigrationInfo(confidence: .verified)
        )
    }
}
