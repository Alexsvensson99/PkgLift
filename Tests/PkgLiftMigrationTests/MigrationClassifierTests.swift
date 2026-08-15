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
            targets: ["App"]
        )
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire.git",
                products: ["Alamofire"],
                minimumVersion: "1.0.0"
            ),
            migration: MigrationInfo(confidence: .verified)
        )
        
        let result = classifier.classify(
            dependency: dependency,
            mapping: mapping,
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
                minimumVersion: "1.0.0"
            ),
            migration: MigrationInfo(confidence: .verified)
        )
        
        let result = classifier.classify(
            dependency: dependency,
            mapping: mapping,
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
                minimumVersion: "1.0.0"
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
                minimumVersion: "1.0.0"
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        let result = MigrationClassifier().classify(dependency: dependency, mapping: mapping)
        XCTAssertEqual(result.category, .review)
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
                minimumVersion: "1.0.0"
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        let result = MigrationClassifier().classify(dependency: dependency, mapping: mapping)
        XCTAssertEqual(result.category, .review)
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
                minimumVersion: "1.0.0"
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        XCTAssertEqual(
            MigrationClassifier().classify(dependency: dependency, mapping: mapping).category,
            .review
        )
    }

    func testMissingMinimumVersionIsReviewOnly() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.1.0"),
            mapping: makeMapping(minimumVersion: nil)
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reason.contains("no verified minimum"))
    }

    func testVersionBelowMinimumIsReview() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.0.6"),
            mapping: makeMapping(minimumVersion: "5.1.0")
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reason.contains("predates"))
    }

    func testVersionEqualToMinimumIsAuto() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.1.0"),
            mapping: makeMapping(minimumVersion: "5.1.0")
        )

        XCTAssertEqual(result.category, .auto)
        XCTAssertTrue(result.reason.contains("meets minimum"))
    }

    func testVersionAboveMinimumIsAuto() {
        XCTAssertEqual(
            MigrationClassifier().classify(
                dependency: makeDependency(version: "5.18.1"),
                mapping: makeMapping(minimumVersion: "5.1.0")
            ).category,
            .auto
        )
    }

    func testInvalidMinimumVersionIsReview() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.18.1"),
            mapping: makeMapping(minimumVersion: "5.1")
        )

        XCTAssertEqual(result.category, .review)
        XCTAssertTrue(result.reason.contains("minimum SwiftPM version is invalid"))
    }

    func testNonStableResolvedVersionIsReview() {
        let result = MigrationClassifier().classify(
            dependency: makeDependency(version: "5.1.0-beta.1"),
            mapping: makeMapping(minimumVersion: "5.1.0")
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
                minimumVersion: "5.1.0"
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
                podfileFeatures: features
            )
            XCTAssertEqual(result.category, .review, "Expected \(label) to block AUTO")
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
            targets: ["App"]
        )
    }

    private func makeMapping(minimumVersion: String?) -> RegistryMapping {
        RegistryMapping(
            pod: PodIdentifier(name: "SDWebImage"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/SDWebImage/SDWebImage",
                products: ["SDWebImage"],
                minimumVersion: minimumVersion
            ),
            migration: MigrationInfo(confidence: .verified)
        )
    }
}
