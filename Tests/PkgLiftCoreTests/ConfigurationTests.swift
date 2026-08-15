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

        XCTAssertThrowsError(try ConfigurationLoader().load(from: file.path))
    }
}
