import Foundation
import XCTest
import PkgLiftCore
@testable import PkgLiftXcode

final class UnsupportedProjectFormatTests: XCTestCase {
    func testAnalyzerAndBothEditorOperationsRejectSecondProjectDefinitionWithoutWrites() throws {
        for name in ["project.xcproj", "alternate.xcproj", "PROJECT.XCPROJ"] {
            try withProject { _, project in
                try Data("unsupported definition".utf8).write(to: project.appendingPathComponent(name))
                let before = try snapshot(project)
                try assertAllEntryPointsRefuse(project)
                XCTAssertEqual(try snapshot(project), before, name)
            }
        }
    }

    func testDanglingJSONDefinitionLinkIsRefusedWithoutFollowingIt() throws {
        try withProject { root, project in
            try FileManager.default.createSymbolicLink(
                at: project.appendingPathComponent("project.xcproj"),
                withDestinationURL: root.appendingPathComponent("missing.json")
            )
            let before = try snapshot(project)
            try assertAllEntryPointsRefuse(project)
            XCTAssertEqual(try snapshot(project), before)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("missing.json").path))
        }
    }

    func testSymlinkedProjectBundleStillRefusesJSONDefinition() throws {
        try withProject { root, project in
            try Data("unsupported definition".utf8).write(to: project.appendingPathComponent("project.xcproj"))
            let alias = root.appendingPathComponent("Alias.xcodeproj")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: project)
            let before = try snapshot(project)
            try assertAllEntryPointsRefuse(alias)
            XCTAssertEqual(try snapshot(project), before)
        }
    }

    func testOrdinaryPBXProjectKeepsExistingAnalysisAndEditingBehavior() throws {
        try withProject { _, project in
            let analysis = try XcodeProjectAnalyzer().analyzeProject(at: project.path)
            XCTAssertEqual(analysis.projectInfo.targets.map(\.name), ["SwiftKeychainAccess"])
            let editor = XcodeProjectEditor()
            try editor.addSwiftPMPackage(
                repositoryURL: "https://github.com/kishikawakatsumi/KeychainAccess",
                requirement: .exact("4.2.2"), to: project.path
            )
            try editor.linkSwiftPMProduct(
                productName: "KeychainAccess", toTarget: "SwiftKeychainAccess",
                repositoryURL: "https://github.com/kishikawakatsumi/KeychainAccess", in: project.path
            )
            let after = try XcodeProjectAnalyzer().analyzeProject(at: project.path)
            XCTAssertEqual(after.swiftPMState.packages.count, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("project.xcproj").path))
        }
    }

    private func assertAllEntryPointsRefuse(_ project: URL) throws {
        let editor = XcodeProjectEditor()
        let operations: [() throws -> Void] = [
            { _ = try XcodeProjectAnalyzer().analyzeProject(at: project.path) },
            { try editor.addSwiftPMPackage(repositoryURL: "https://github.com/kishikawakatsumi/KeychainAccess",
                                          requirement: .exact("4.2.2"), to: project.path) },
            { try editor.linkSwiftPMProduct(productName: "KeychainAccess", toTarget: "SwiftKeychainAccess",
                                            repositoryURL: "https://github.com/kishikawakatsumi/KeychainAccess",
                                            in: project.path) },
        ]
        for operation in operations {
            XCTAssertThrowsError(try operation()) { error in
                XCTAssertTrue(error is UnsupportedXcodeProjectFormatError, "Unexpected error: \(error)")
                XCTAssertTrue(error.localizedDescription.contains("project.xcproj"))
            }
        }
    }

    private func withProject(_ body: (URL, URL) throws -> Void) throws {
        let temporaryRoot = ProcessInfo.processInfo.environment["PKGLIFT_TEST_TEMP_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: temporaryRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw CocoaError(.fileNoSuchFile) }
        let root = temporaryRoot.appendingPathComponent("PkgLiftFormat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let project = root.appendingPathComponent("SwiftKeychainAccess.xcodeproj")
        try FileManager.default.copyItem(
            at: sourceRoot.appendingPathComponent("Fixtures/PartialSwift/SwiftKeychainAccess.xcodeproj"), to: project
        )
        try body(root, project)
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            throw CocoaError(.fileReadUnknown)
        }
        for case let item as URL in enumerator {
            let name = String(item.path.dropFirst(root.path.count + 1))
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                result[name] = Data(try FileManager.default.destinationOfSymbolicLink(atPath: item.path).utf8)
            } else if values.isDirectory != true {
                result[name] = try Data(contentsOf: item)
            }
        }
        return result
    }
}
