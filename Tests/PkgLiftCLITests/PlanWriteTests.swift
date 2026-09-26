import Darwin
import Foundation
import XCTest
@testable import PkgLiftCLI

final class PlanWriteTests: XCTestCase {
    func testCommandRefusesParentLinksInEveryOutputMode() async throws {
        for flags in [[], ["--json"], ["--portable-json"]] {
            for absolute in [false, true] {
                let fixture = try Fixture()
                defer { fixture.cleanup() }
                try FileManager.default.createSymbolicLink(
                    atPath: fixture.state.path,
                    withDestinationPath: absolute ? fixture.outside.path : "../outside"
                )
                var command = try PlanCommand.parse(["--path", fixture.project.path] + flags)
                do {
                    try await command.run()
                    XCTFail("A parent link must be refused before writing a plan")
                } catch {
                    XCTAssertEqual(error as? PlanWriteError, .unsafeLocation)
                }
                XCTAssertEqual(try Data(contentsOf: fixture.sentinel), fixture.original)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.outside.path), ["plan.json"])
            }
        }
    }

    func testDanglingAndInternalParentLinksAreRefused() throws {
        for destination in ["../missing", "real-state"] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let internalState = fixture.project.appendingPathComponent("real-state")
            try FileManager.default.createDirectory(at: internalState, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(atPath: fixture.state.path, withDestinationPath: destination)
            XCTAssertThrowsError(try PlanFileWriter(canonicalRoot: fixture.project.path)) {
                XCTAssertEqual($0 as? PlanWriteError, .unsafeLocation)
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: internalState.path), [])
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.base.appendingPathComponent("missing").path))
        }
    }

    func testNonDirectoryStateIsRefusedWithoutBlocking() throws {
        for fifo in [false, true] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            if fifo {
                XCTAssertEqual(mkfifo(fixture.state.path, mode_t(0o600)), 0)
            } else {
                try fixture.original.write(to: fixture.state)
            }
            XCTAssertThrowsError(try PlanFileWriter(canonicalRoot: fixture.project.path)) {
                XCTAssertEqual($0 as? PlanWriteError, .unsafeLocation)
            }
            if !fifo { XCTAssertEqual(try Data(contentsOf: fixture.state), fixture.original) }
        }
    }

    func testDestinationLinksDirectoriesAndFIFOsAreRefused() throws {
        for kind in ["absolute-link", "dangling-link", "directory", "fifo"] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let writer = try PlanFileWriter(canonicalRoot: fixture.project.path)
            switch kind {
            case "absolute-link":
                try FileManager.default.createSymbolicLink(at: fixture.plan, withDestinationURL: fixture.sentinel)
            case "dangling-link":
                try FileManager.default.createSymbolicLink(atPath: fixture.plan.path, withDestinationPath: "../../missing-plan.json")
            case "directory":
                try FileManager.default.createDirectory(at: fixture.plan, withIntermediateDirectories: false)
            default:
                XCTAssertEqual(mkfifo(fixture.plan.path, mode_t(0o600)), 0)
            }
            XCTAssertThrowsError(try writer.stage(Data("replacement".utf8))) {
                XCTAssertEqual($0 as? PlanWriteError, .unsafeLocation)
            }
            XCTAssertEqual(try Data(contentsOf: fixture.sentinel), fixture.original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.base.appendingPathComponent("missing-plan.json").path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.state.path), ["plan.json"])
        }
    }

    func testNormalCommandsCreateAndReplacePlansIncludingRootAlias() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let alias = fixture.base.appendingPathComponent("project-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.project)
        // A selected-root alias is legitimate; only the state/output child
        // bindings must be refused when they are symlinks.
        let writer = try PlanFileWriter(canonicalRoot: alias.path)
        try writer.stage(Data("initial plan".utf8)).publish()
        for flags in [[], ["--json"], ["--portable-json"]] {
            var command = try PlanCommand.parse(["--path", alias.path] + flags)
            try await command.run()
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.plan)))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.sentinel), fixture.original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.state.path), ["plan.json"])
    }

    func testAtomicReplacementPreservesHardLinkAndUnrelatedState() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(at: fixture.state, withIntermediateDirectories: false)
        try FileManager.default.linkItem(at: fixture.sentinel, to: fixture.plan)
        let unrelated = fixture.state.appendingPathComponent("registry-note")
        try fixture.original.write(to: unrelated)
        let writer = try PlanFileWriter(canonicalRoot: fixture.project.path)
        let bytes = Data("new plan bytes".utf8)
        let staged = try writer.stage(bytes)
        XCTAssertEqual(try Data(contentsOf: fixture.plan), fixture.original)
        try staged.publish()
        XCTAssertEqual(try Data(contentsOf: fixture.plan), bytes)
        XCTAssertEqual(try Data(contentsOf: fixture.sentinel), fixture.original)
        XCTAssertEqual(try Data(contentsOf: unrelated), fixture.original)
        XCTAssertThrowsError(try staged.publish())
    }

    func testChangedDirectoryBindingsRefuseBeforePublication() throws {
        for component in ["state", "root", "ancestor"] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let writer = try PlanFileWriter(canonicalRoot: fixture.project.path)
            try fixture.original.write(to: fixture.plan)
            let staged = try writer.stage(Data("new plan bytes".utf8))
            let moved: URL
            let original: URL
            if component == "state" {
                original = fixture.state
                moved = fixture.project.appendingPathComponent("old-state")
            } else if component == "root" {
                original = fixture.project
                moved = fixture.base.appendingPathComponent("old-project")
            } else {
                original = fixture.base
                moved = fixture.base.appendingPathExtension("moved")
            }
            try FileManager.default.moveItem(at: original, to: moved)
            defer {
                try? FileManager.default.removeItem(at: original)
                try? FileManager.default.moveItem(at: moved, to: original)
            }
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: fixture.outside)
            XCTAssertThrowsError(try staged.publish()) {
                XCTAssertEqual($0 as? PlanWriteError, .changedBinding)
            }
            let oldPlan = component == "state" ? moved.appendingPathComponent("plan.json")
                : component == "root" ? moved.appendingPathComponent(".pkglift/plan.json")
                : moved.appendingPathComponent("project/.pkglift/plan.json")
            XCTAssertEqual(try Data(contentsOf: oldPlan), fixture.original)
        }
    }

    func testStateRebindingBeforeStagingDoesNotCreateTemporaryFiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let writer = try PlanFileWriter(canonicalRoot: fixture.project.path)
        let moved = fixture.project.appendingPathComponent("old-state")
        try FileManager.default.moveItem(at: fixture.state, to: moved)
        try FileManager.default.createSymbolicLink(at: fixture.state, withDestinationURL: fixture.outside)
        XCTAssertThrowsError(try writer.stage(Data("new plan bytes".utf8)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: moved.path), [])
        XCTAssertEqual(try Data(contentsOf: fixture.sentinel), fixture.original)
    }

    func testChangedDestinationPreservesNewEntryAndCleansOwnedTemporary() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let writer = try PlanFileWriter(canonicalRoot: fixture.project.path)
        do {
            let staged = try writer.stage(Data("new plan bytes".utf8))
            try fixture.original.write(to: fixture.plan)
            XCTAssertThrowsError(try staged.publish()) {
                XCTAssertEqual($0 as? PlanWriteError, .changedBinding)
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.plan), fixture.original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.state.path), ["plan.json"])
    }

    func testReplacedTemporaryIsNeitherPublishedNorRemoved() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let writer = try PlanFileWriter(canonicalRoot: fixture.project.path)
        try fixture.original.write(to: fixture.plan)
        let temporary: URL
        do {
            let staged = try writer.stage(Data("new plan bytes".utf8))
            let name = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: fixture.state.path)
                .first { $0.hasPrefix(".plan-") })
            temporary = fixture.state.appendingPathComponent(name)
            try FileManager.default.removeItem(at: temporary)
            try FileManager.default.createSymbolicLink(at: temporary, withDestinationURL: fixture.sentinel)
            XCTAssertThrowsError(try staged.publish()) {
                XCTAssertEqual($0 as? PlanWriteError, .changedBinding)
            }
        }
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: temporary.path), fixture.sentinel.path)
        XCTAssertEqual(try Data(contentsOf: fixture.plan), fixture.original)
        XCTAssertEqual(try Data(contentsOf: fixture.sentinel), fixture.original)
    }

    private struct Fixture {
        let base: URL
        let original = Data("owned sentinel".utf8)
        var project: URL { base.appendingPathComponent("project") }
        var outside: URL { base.appendingPathComponent("outside") }
        var state: URL { project.appendingPathComponent(".pkglift") }
        var plan: URL { state.appendingPathComponent("plan.json") }
        var sentinel: URL { outside.appendingPathComponent("plan.json") }

        init() throws {
            let temporary = ProcessInfo.processInfo.environment["TMPDIR"].map {
                URL(fileURLWithPath: $0, isDirectory: true)
            } ?? FileManager.default.temporaryDirectory
            base = temporary.resolvingSymlinksInPath().appendingPathComponent("PkgLiftPlanWrite-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
            try original.write(to: sentinel)
        }

        func cleanup() { try? FileManager.default.removeItem(at: base) }
    }
}
