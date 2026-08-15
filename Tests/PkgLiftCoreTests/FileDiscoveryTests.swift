import Foundation
import XCTest
@testable import PkgLiftCore

final class FileDiscoveryTests: XCTestCase {
    func testDiscoversProjectFilesInRoot() throws {
        let root = try makeDirectory(prefix: "PkgLiftDiscovery")
        defer { try? FileManager.default.removeItem(at: root) }
        try "pod 'Alamofire'".write(
            to: root.appendingPathComponent("Podfile"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("App.xcodeproj"),
            withIntermediateDirectories: true
        )

        let result = try FileDiscovery().discover(in: root.path)

        XCTAssertEqual(result.podfilePath, root.appendingPathComponent("Podfile").path)
        XCTAssertEqual(result.projectPaths, [root.appendingPathComponent("App.xcodeproj").path])
    }

    func testPodfileSymlinkOutsideRootIsNotDiscovered() throws {
        let root = try makeDirectory(prefix: "PkgLiftDiscoveryRoot")
        let outside = try makeDirectory(prefix: "PkgLiftDiscoveryOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let outsidePodfile = outside.appendingPathComponent("Podfile")
        try "pod 'Alamofire'".write(to: outsidePodfile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Podfile"),
            withDestinationURL: outsidePodfile
        )

        let result = try FileDiscovery().discover(in: root.path)

        XCTAssertNil(result.podfilePath)
    }

    func testRecursivelyDiscoversProjectsAndWorkspacesInStableOrder() throws {
        let root = try makeDirectory(prefix: "PkgLiftRecursiveDiscovery")
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("Apps/Nested")
        try FileManager.default.createDirectory(
            at: nested.appendingPathComponent("Beta.xcodeproj"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Apps/Alpha.xcodeproj"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: nested.appendingPathComponent("Products.xcworkspace"),
            withIntermediateDirectories: true
        )

        let result = try FileDiscovery().discover(in: root.path)

        XCTAssertEqual(result.projectPaths, [
            root.appendingPathComponent("Apps/Alpha.xcodeproj").path,
            nested.appendingPathComponent("Beta.xcodeproj").path,
        ])
        XCTAssertEqual(result.workspacePaths, [
            nested.appendingPathComponent("Products.xcworkspace").path,
        ])
    }

    func testRecursiveDiscoverySkipsGeneratedTreesProjectInternalsAndSymlinks() throws {
        let root = try makeDirectory(prefix: "PkgLiftRecursiveDiscoveryRoot")
        let outside = try makeDirectory(prefix: "PkgLiftRecursiveDiscoveryOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let generatedPaths = [
            "Pods/Pods.xcodeproj",
            ".build/checkouts/Dependency.xcodeproj",
            "Carthage/Checkouts/Legacy.xcodeproj",
            "DerivedData/App/Build.xcworkspace",
            "App.xcodeproj/project.xcworkspace",
        ]
        for path in generatedPaths {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(path),
                withIntermediateDirectories: true
            )
        }

        let outsideProject = outside.appendingPathComponent("Outside.xcodeproj")
        try FileManager.default.createDirectory(at: outsideProject, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Linked.xcodeproj"),
            withDestinationURL: outsideProject
        )

        let result = try FileDiscovery().discover(in: root.path)

        XCTAssertEqual(result.projectPaths, [root.appendingPathComponent("App.xcodeproj").path])
        XCTAssertTrue(result.workspacePaths.isEmpty)
    }

    private func makeDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
