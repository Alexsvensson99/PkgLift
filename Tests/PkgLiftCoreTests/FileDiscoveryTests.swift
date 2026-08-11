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

    private func makeDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
