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

    func testConfirmedProjectIntegrationsPreventAutoWithStableReasons() {
        for integration in ProjectIntegration.allCases {
            let result = MigrationClassifier().classify(
                dependency: makeDependency(version: "5.18.1"),
                mapping: makeMapping(minimumVersion: "5.1.0"),
                targetSourceProfile: swiftProfile,
                projectIntegrations: [integration]
            )

            XCTAssertEqual(result.category, .review)
            XCTAssertTrue(result.reasons.contains(integration.reviewReason))
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

    func testTypedReasonsPreserveLegacyMessagesAndStableOrder() {
        var features = PodfileFeatures()
        features.hasPostInstallHook = true
        features.hasDynamicRuby = true
        let result = MigrationClassifier().classify(
            dependency: CocoaPodDependency(
                name: "ExternalKit",
                version: "1.2.3",
                source: .git(url: "https://example.invalid/ExternalKit.git", ref: nil),
                targets: []
            ),
            mapping: nil,
            podfileFeatures: features
        )

        XCTAssertEqual(result.reasonDetails.map(\.message), result.reasons)
        XCTAssertEqual(result.reasonDetails.map(\.code), [
            .externalSourceWithoutMapping,
            .registryMappingMissing,
            .podfileInstallHook,
            .podfileDynamicRuby,
            .targetAttributionUnresolved,
        ])
        XCTAssertTrue(result.reasonDetails.dropLast().allSatisfy { $0.remediation != nil })
    }

    func testEveryNewRegistryIdentityIsAutoOnlyWithExactVerifiedEvidence() {
        struct MappingCase {
            let name: String
            let product: String
            let minimumVersion: String
            let supportedLanguages: [SourceLanguage]
            let targetProfile: TargetSourceProfile
            let belowMinimum: String
        }

        let mixedProfile = TargetSourceProfile(
            languages: [.swift, .objectiveC],
            completeness: .complete
        )
        let firebaseNames = [
            ("FirebaseAuth", "FirebaseAuth"),
            ("Firebase/Auth", "FirebaseAuth"),
            ("FirebaseFirestore", "FirebaseFirestore"),
            ("Firebase/Firestore", "FirebaseFirestore"),
            ("FirebaseRemoteConfig", "FirebaseRemoteConfig"),
            ("Firebase/RemoteConfig", "FirebaseRemoteConfig"),
            ("FirebaseStorage", "FirebaseStorage"),
            ("Firebase/Storage", "FirebaseStorage"),
        ]
        let cases = [
            MappingCase(
                name: "lottie-ios",
                product: "Lottie",
                minimumVersion: "3.2.2",
                supportedLanguages: [.swift],
                targetProfile: swiftProfile,
                belowMinimum: "3.2.1"
            ),
        ] + firebaseNames.map { name, product in
            MappingCase(
                name: name,
                product: product,
                minimumVersion: "11.12.0",
                supportedLanguages: [.swift, .objectiveC],
                targetProfile: mixedProfile,
                belowMinimum: "11.11.0"
            )
        }

        for testCase in cases {
            let identity = testCase.name.split(separator: "/", maxSplits: 1).map(String.init)
            let mapping = RegistryMapping(
                pod: PodIdentifier(
                    name: identity[0],
                    subspec: identity.count == 2 ? identity[1] : nil
                ),
                swiftpm: SwiftPMPackageInfo(
                    repository: testCase.name == "lottie-ios"
                        ? "https://github.com/airbnb/lottie-ios"
                        : "https://github.com/firebase/firebase-ios-sdk",
                    products: [testCase.product],
                    minimumVersion: testCase.minimumVersion,
                    supportedConsumerLanguages: testCase.supportedLanguages
                ),
                migration: MigrationInfo(confidence: .verified)
            )

            let positive = MigrationClassifier().classify(
                dependency: makeDependency(name: testCase.name, version: testCase.minimumVersion),
                mapping: mapping,
                targetSourceProfile: testCase.targetProfile
            )
            XCTAssertEqual(positive.category, .auto, testCase.name)
            XCTAssertEqual(positive.reasonDetails.map(\.code), [.verifiedAutomaticMigration])

            let negative = MigrationClassifier().classify(
                dependency: makeDependency(name: testCase.name, version: testCase.belowMinimum),
                mapping: mapping,
                targetSourceProfile: testCase.targetProfile
            )
            XCTAssertEqual(negative.category, .review, testCase.name)
            XCTAssertTrue(negative.reasonDetails.contains { $0.code == .versionBelowMinimum })

            let failClosed = MigrationClassifier().classify(
                dependency: makeDependency(name: testCase.name, version: testCase.minimumVersion),
                mapping: mapping,
                targetSourceProfile: TargetSourceProfile(
                    languages: [.c],
                    completeness: .complete
                )
            )
            XCTAssertEqual(failClosed.category, .review, testCase.name)
            XCTAssertTrue(failClosed.reasonDetails.contains { $0.code == .targetLanguageUnsupported })
        }
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
