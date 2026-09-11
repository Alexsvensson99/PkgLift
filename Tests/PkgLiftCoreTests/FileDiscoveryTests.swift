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

    func testDetectsOnlyContainedRootCarthageMetadataWithoutReadingIt() throws {
        let root = try makeDirectory(prefix: "PkgLiftCarthageRoot")
        let outside = try makeDirectory(prefix: "PkgLiftCarthageOutside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        try Data([0xFF]).write(to: root.appendingPathComponent("Cartfile"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Nested"),
            withIntermediateDirectories: true
        )
        try "github \"Example/Dependency\"".write(
            to: root.appendingPathComponent("Nested/Cartfile.resolved"),
            atomically: true,
            encoding: .utf8
        )
        let outsideResolved = outside.appendingPathComponent("Cartfile.resolved")
        try "private canary".write(
            to: outsideResolved,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Cartfile.resolved"),
            withDestinationURL: outsideResolved
        )

        let result = try FileDiscovery().discover(in: root.path)

        XCTAssertTrue(result.hasCartfile)
        XCTAssertFalse(result.hasCartfileResolved)
        XCTAssertTrue(result.hasCarthageFiles)
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

    func testRecursiveDiscoveryIgnoresPkgLiftRecoveryProjectsAndPreservesRecoveryData() throws {
        let root = try makeDirectory(prefix: "PkgLiftRecoveryDiscovery")
        defer { try? FileManager.default.removeItem(at: root) }

        let recoveryRoot = root.appendingPathComponent(".pkglift")
        let recoveryDirectory = recoveryRoot.appendingPathComponent("backup")
        let recoveryMarker = recoveryRoot.appendingPathComponent("migration-in-progress")
        let recoveryContents = Data("recovery state".utf8)
        try FileManager.default.createDirectory(
            at: recoveryDirectory.appendingPathComponent("Recovered.xcodeproj"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: recoveryDirectory.appendingPathComponent("Recovered.xcworkspace"),
            withIntermediateDirectories: true
        )
        try recoveryContents.write(to: recoveryMarker)

        let project = root.appendingPathComponent("App/App.xcodeproj")
        let workspace = root.appendingPathComponent("App/App.xcworkspace")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let result = try FileDiscovery().discover(in: root.path)

        XCTAssertEqual(result.projectPaths, [project.path])
        XCTAssertEqual(result.workspacePaths, [workspace.path])
        XCTAssertEqual(try Data(contentsOf: recoveryMarker), recoveryContents)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryDirectory.path))
    }

    private func makeDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension FileDiscoveryTests {
    func testMissingRootThrowsNotADirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        XCTAssertThrowsError(try FileDiscovery().discover(in: root.path)) { error in
            guard case let FileDiscoveryError.notADirectory(path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, root.path)
        }
    }

    func testRegularFileRootThrowsNotADirectory() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let file = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: file)

        XCTAssertThrowsError(try FileDiscovery().discover(in: file.path)) { error in
            guard case let FileDiscoveryError.notADirectory(path) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, file.path)
        }
    }

    func testManifestLockSymlinkOutsidePodsIsNotDiscovered() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Pods", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: outside)
        }

        let outsideManifest = outside.appendingPathComponent("Manifest.lock")
        try "COCOAPODS: 1.16.2".write(to: outsideManifest, atomically: true, encoding: .utf8)
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("Pods/Manifest.lock"),
            withDestinationURL: outsideManifest
        )

        let result = try FileDiscovery().discover(in: root.path)

        XCTAssertNil(result.manifestLockPath)
    }
}
