import XCTest
import PkgLiftCore
@testable import PkgLiftRegistry

final class RegistryValidatorTests: XCTestCase {
    
    func testValidMapping() {
        let mapping = RegistryMapping(
            schemaVersion: 1,
            pod: PodIdentifier(name: "ValidPod"),
            swiftpm: SwiftPMPackageInfo(repository: "https://github.com/org/repo", products: ["Product"]),
            migration: MigrationInfo(confidence: .verified)
        )
        
        let validator = RegistryValidator()
        let errors = validator.validate(mapping, filePath: "test.yml")
        XCTAssertTrue(errors.isEmpty)
    }
    
    func testInvalidMapping() {
        let mapping = RegistryMapping(
            schemaVersion: 2, // Invalid schema
            pod: PodIdentifier(name: ""), // Invalid name
            swiftpm: SwiftPMPackageInfo(repository: "invalid-url", products: []), // Invalid repo & products
            migration: MigrationInfo(confidence: .verified)
        )
        
        let validator = RegistryValidator()
        let errors = validator.validate(mapping, filePath: "test.yml")
        
        XCTAssertEqual(errors.count, 4)
        XCTAssertTrue(errors.contains(where: { $0.fieldPath == "schemaVersion" }))
        XCTAssertTrue(errors.contains(where: { $0.fieldPath == "pod.name" }))
        XCTAssertTrue(errors.contains(where: { $0.fieldPath == "swiftpm.repository" }))
        XCTAssertTrue(errors.contains(where: { $0.fieldPath == "swiftpm.products" }))
    }

    func testIncompleteHTTPSRepositoryURLIsInvalid() {
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "UnsafePod"),
            swiftpm: SwiftPMPackageInfo(repository: "https://", products: ["UnsafePod"]),
            migration: MigrationInfo(confidence: .verified)
        )

        let errors = RegistryValidator().validate(mapping, filePath: "UnsafePod.yml")
        XCTAssertTrue(errors.contains { $0.fieldPath == "swiftpm.repository" })
    }

    func testMalformedMinimumVersionIsInvalidWhenPresent() {
        for value in [
            "5.1",
            "5.1.0-beta.1",
            "5.1.0+build.42",
            "v5.1.0",
            "5.1.0.1",
            "5..1",
            " 5.1.0",
            "5.1.0 ",
            "05.1.0",
            "5.01.0",
            "5.1.00",
        ] {
            let mapping = RegistryMapping(
                pod: PodIdentifier(name: "UnsafePod"),
                swiftpm: SwiftPMPackageInfo(
                    repository: "https://github.com/org/repo",
                    products: ["UnsafePod"],
                    minimumVersion: value
                ),
                migration: MigrationInfo(confidence: .verified)
            )

            let errors = RegistryValidator().validate(mapping, filePath: "UnsafePod.yml")
            XCTAssertTrue(
                errors.contains { $0.fieldPath == "swiftpm.minimumVersion" },
                "Expected \(value) to be rejected"
            )
        }
    }

    func testStrictStableMinimumVersionFormatsAreAccepted() {
        for value in ["0.0.0", "1.2.3", "2147483647.0.999"] {
            let mapping = RegistryMapping(
                pod: PodIdentifier(name: "StableVersionPod"),
                swiftpm: SwiftPMPackageInfo(
                    repository: "https://github.com/org/repo",
                    products: ["StableVersionPod"],
                    minimumVersion: value
                ),
                migration: MigrationInfo(confidence: .verified)
            )

            let errors = RegistryValidator().validate(mapping, filePath: "StableVersionPod.yml")
            XCTAssertFalse(
                errors.contains { $0.fieldPath == "swiftpm.minimumVersion" },
                "Expected \(value) to be accepted"
            )
        }
    }

    func testConsumerLanguagesAreOptionalForLegacyMappings() {
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "LegacyPod"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/org/repo",
                products: ["LegacyPod"]
            ),
            migration: MigrationInfo(confidence: .verified)
        )

        let errors = RegistryValidator().validate(mapping, filePath: "LegacyPod.yml")

        XCTAssertFalse(errors.contains { $0.fieldPath == "swiftpm.supportedConsumerLanguages" })
    }

    func testEmptyAndDuplicateConsumerLanguagesAreInvalid() {
        let packages = [
            SwiftPMPackageInfo(
                repository: "https://github.com/org/repo",
                products: ["Empty"],
                supportedConsumerLanguages: []
            ),
            SwiftPMPackageInfo(
                repository: "https://github.com/org/repo",
                products: ["Duplicate"],
                supportedConsumerLanguages: [.swift, .swift]
            ),
        ]

        for package in packages {
            let mapping = RegistryMapping(
                pod: PodIdentifier(name: "InvalidLanguages"),
                swiftpm: package,
                migration: MigrationInfo(confidence: .verified)
            )

            let errors = RegistryValidator().validate(mapping, filePath: "InvalidLanguages.yml")
            XCTAssertTrue(errors.contains {
                $0.fieldPath == "swiftpm.supportedConsumerLanguages"
            })
        }
    }
}
