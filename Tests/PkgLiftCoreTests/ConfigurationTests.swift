import Foundation
import XCTest
@testable import PkgLiftCore

final class ConfigurationTests: XCTestCase {
    func testValidMigrationAllowAndDenyListsLoad() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftConfig-\(UUID().uuidString).yml")
        defer { try? FileManager.default.removeItem(at: file) }
        try """
        schemaVersion: 1
        migration:
          allow: [Alamofire]
          deny: [UnsafePod]
        """.write(to: file, atomically: true, encoding: .utf8)

        let configuration = try ConfigurationLoader().load(from: file.path)

        XCTAssertEqual(configuration.migration?.allow, ["Alamofire"])
        XCTAssertEqual(configuration.migration?.deny, ["UnsafePod"])
    }

    func testUnsupportedSchemaVersionThrows() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftConfig-\(UUID().uuidString).yml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "schemaVersion: 99".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ConfigurationLoader().load(from: file.path)) { error in
            guard case ConfigurationError.unsupportedSchemaVersion(99) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMissingConfigurationFileThrowsTypedReadError() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingPkgLiftConfig-\(UUID().uuidString).yml")

        XCTAssertThrowsError(try ConfigurationLoader().load(from: file.path)) { error in
            guard case ConfigurationError.fileReadFailed(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, file.path)
        }
    }

    func testInvalidUTF8ThrowsTypedConfigurationError() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftConfig-\(UUID().uuidString).yml")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([0xFF, 0xFE, 0x00]).write(to: file)

        XCTAssertThrowsError(try ConfigurationLoader().load(from: file.path)) { error in
            guard case ConfigurationError.invalidEncoding(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, file.path)
        }
    }

    func testMalformedYAMLIsRejected() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftConfig-\(UUID().uuidString).yml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "schemaVersion: [1".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ConfigurationLoader().load(from: file.path)) { error in
            guard case ConfigurationError.parsingFailed(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, file.path)
        }
    }

    func testWrongConfigurationFieldTypeIsRejected() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftConfig-\(UUID().uuidString).yml")
        defer { try? FileManager.default.removeItem(at: file) }
        try """
        schemaVersion: 1
        verification:
          build: [true]
        """.write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ConfigurationLoader().load(from: file.path)) { error in
            guard case ConfigurationError.parsingFailed(let path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, file.path)
        }
    }
}
