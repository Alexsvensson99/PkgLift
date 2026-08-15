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
        for value in ["5.1", "5.1.0-beta.1", " 5.1.0", "05.1.0"] {
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
}
