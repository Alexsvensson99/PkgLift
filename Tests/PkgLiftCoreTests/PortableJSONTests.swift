import Foundation
import XCTest
@testable import PkgLiftCore

final class PortableJSONTests: XCTestCase {
    func testPortableOutputRedactsLocalPathsAndURLSecretsDeterministically() throws {
        let source: [String: Any] = [
            "projectPath": "/Users/alex/Secret Client/App.xcodeproj",
            "workspacePath": "~/Secret Client/App.xcworkspace",
            "paths": [
                "./Private/config.json",
                "../Private/plan.json",
                #"C:\Users\alex\Secret\App.xcodeproj"#,
                #"..\Private\plan.json"#,
                #"\\fileserver\secret\App.xcworkspace"#,
            ],
            "fileURL": "file:///Users/alex/Secret%20Client/Podfile",
            "repositoryURL": "https://user:password@example.com/org/repo.git?token=secret#private",
            "scpRepository": "git@github.com:org/repo.git",
            "dependency": "Moya/RxSwift",
            "target": "CustomerApp",
            "reason": "A/B comparison remains useful",
            "nested": [["rootPath": "relative/private/project"]],
        ]
        let data = try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys])
        let renderer = PortableJSON()

        let first = try renderer.render(data)
        let second = try renderer.render(data)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: first) as? [String: Any]
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            (object["portableOutput"] as? [String: Any])?["version"] as? Int,
            1
        )
        XCTAssertEqual(object["projectPath"] as? String, PortableJSON.redactedPath)
        XCTAssertEqual(object["workspacePath"] as? String, PortableJSON.redactedPath)
        XCTAssertEqual(
            object["paths"] as? [String],
            Array(repeating: PortableJSON.redactedPath, count: 5)
        )
        XCTAssertEqual(object["fileURL"] as? String, "file://<redacted-path>")
        XCTAssertEqual(
            object["repositoryURL"] as? String,
            "https://example.com/org/repo.git"
        )
        XCTAssertEqual(
            object["scpRepository"] as? String,
            "ssh://github.com/org/repo.git"
        )
        XCTAssertEqual(object["dependency"] as? String, "Moya/RxSwift")
        XCTAssertEqual(object["target"] as? String, "CustomerApp")
        XCTAssertEqual(object["reason"] as? String, "A/B comparison remains useful")

        let nested = try XCTUnwrap(object["nested"] as? [[String: Any]])
        XCTAssertEqual(nested[0]["rootPath"] as? String, PortableJSON.redactedPath)

        let json = try XCTUnwrap(String(data: first, encoding: .utf8))
        for secret in ["alex", "password", "token=", "#private", "fileserver", "Secret Client"] {
            XCTAssertFalse(json.contains(secret), "Portable JSON leaked \(secret)")
        }
    }

    func testStandardOutputIsByteIdenticalWhenPortableModeIsDisabled() throws {
        let original = Data(#"{"z":"/private/path","a":1}"#.utf8)

        let output = try PortableJSON().output(from: original, portable: false)

        XCTAssertEqual(output, original)
    }

    func testPortableOutputRejectsNonObjectRoot() throws {
        let data = try JSONSerialization.data(withJSONObject: ["/private/path"])

        XCTAssertThrowsError(try PortableJSON().render(data)) { error in
            XCTAssertEqual(error as? PortableJSONError, .rootMustBeObject)
        }
    }
}
