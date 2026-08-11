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
                products: ["Alamofire"]
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
                products: ["Alamofire"]
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
                products: ["Alamofire"]
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
                products: ["Alamofire"]
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
                products: ["Alamofire"]
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
                products: ["Alamofire"]
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        XCTAssertEqual(
            MigrationClassifier().classify(dependency: dependency, mapping: mapping).category,
            .review
        )
    }
}
