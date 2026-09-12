import Foundation
import Testing
@testable import PkgLiftInspection

@Suite("Bounded directory observation")
struct DirectoryObservationTests {
    @Test("Observe one directory without recursion in raw-byte order")
    func observesOneLevelInDeterministicOrder() throws {
        let fixture = try DirectoryFixture()
        defer { fixture.remove() }
        try fixture.write("B.swift")
        try fixture.write("A.swift")
        try fixture.write("Notes.txt")
        try fixture.write("Nested/Inside.swift")

        let directory = try fixture.inspectionDirectory()
        let observation = try directory.observeEntries(
            components: ["Sources"], maximumEntries: 4
        )

        #expect(observation.entryCount == 4)
        #expect(observation.entries.map(\.nameBytes) == [
            Array("A.swift".utf8),
            Array("B.swift".utf8),
            Array("Nested".utf8),
            Array("Notes.txt".utf8),
        ])
        #expect(observation.entries[0].isRegular)
        #expect(observation.entries[2].isDirectory)
        try directory.validateEntries(observation, maximumEntries: 4)
        try directory.validateDirectoryBinding(observation)
    }

    @Test("Count every immediate entry against the hard limit")
    func enforcesEntryLimit() throws {
        let fixture = try DirectoryFixture()
        defer { fixture.remove() }
        try fixture.write("A.swift")
        try fixture.write("Unmatched.txt")
        let directory = try fixture.inspectionDirectory()

        _ = try directory.observeEntries(components: ["Sources"], maximumEntries: 2)
        do {
            _ = try directory.observeEntries(components: ["Sources"], maximumEntries: 1)
            Issue.record("Expected the second directory entry to exceed the limit")
        } catch let failure as LocalSourceInspectionFailure {
            #expect(failure.code == .limitExceeded)
        }
    }

    @Test("Reject a directory change between observation passes")
    func detectsEntrySetChange() throws {
        let fixture = try DirectoryFixture()
        defer { fixture.remove() }
        try fixture.write("A.swift")
        let directory = try fixture.inspectionDirectory()
        let observation = try directory.observeEntries(
            components: ["Sources"], maximumEntries: 2
        )
        try fixture.write("Unmatched.txt")

        do {
            try directory.validateEntries(observation, maximumEntries: 2)
            Issue.record("Expected the changed directory to be rejected")
        } catch let failure as LocalSourceInspectionFailure {
            #expect(failure.code == .changedDuringRead)
        }
    }

    @Test("Strict reads stop at an exact caller byte budget")
    func strictReadAtExactLimit() throws {
        let fixture = try DirectoryFixture()
        defer { fixture.remove() }
        let bytes = Data(repeating: 0x61, count: 65_537)
        try fixture.write("Exact.swift", bytes: bytes)
        let directory = try fixture.inspectionDirectory()

        let read = try directory.read(
            components: ["Sources", "Exact.swift"],
            maximumBytes: bytes.count,
            strictByteLimit: true
        )

        #expect(read.observation.byteCount == bytes.count)
        try directory.validate(
            read.observation,
            maximumBytes: read.observation.byteCount,
            strictByteLimit: true
        )
    }

    @Test(
        "An enumerated file whose path binding changes before its first read is a concurrent change",
        arguments: ["missingFile", "symlinkFile", "missingParent", "symlinkParent"]
    )
    func expectedStampMapsBindingChanges(kind: String) throws {
        let fixture = try DirectoryFixture()
        defer { fixture.remove() }
        try fixture.write("A.swift")
        let directory = try fixture.inspectionDirectory()
        let observation = try directory.observeEntries(
            components: ["Sources"], maximumEntries: 1
        )
        let expectedStamp = try #require(observation.entries.first?.stamp)
        let source = fixture.sources.appendingPathComponent("A.swift")

        switch kind {
        case "missingFile":
            try FileManager.default.removeItem(at: source)
        case "symlinkFile":
            let retained = fixture.base.appendingPathComponent("Retained.swift")
            try FileManager.default.moveItem(at: source, to: retained)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: retained)
        case "missingParent":
            try FileManager.default.removeItem(at: fixture.sources)
        case "symlinkParent":
            let retained = fixture.base.appendingPathComponent("RetainedSources")
            try FileManager.default.moveItem(at: fixture.sources, to: retained)
            try FileManager.default.createSymbolicLink(at: fixture.sources, withDestinationURL: retained)
        default:
            Issue.record("Unknown fixture mutation")
        }

        do {
            _ = try directory.read(
                components: ["Sources", "A.swift"],
                maximumBytes: 1_024,
                expectedStamp: expectedStamp,
                strictByteLimit: true
            )
            Issue.record("Expected the changed path binding to be rejected")
        } catch let failure as LocalSourceInspectionFailure {
            #expect(failure.code == .changedDuringRead)
        }
    }

    @Test("An expected stamp does not turn a stable size violation into a concurrent change")
    func expectedStampPreservesStableLimitFailure() throws {
        let fixture = try DirectoryFixture()
        defer { fixture.remove() }
        try fixture.write("Large.swift", bytes: Data(repeating: 0x61, count: 2))
        let directory = try fixture.inspectionDirectory()
        let observation = try directory.observeEntries(
            components: ["Sources"], maximumEntries: 1
        )
        let expectedStamp = try #require(observation.entries.first?.stamp)

        do {
            _ = try directory.read(
                components: ["Sources", "Large.swift"],
                maximumBytes: 1,
                expectedStamp: expectedStamp,
                strictByteLimit: true
            )
            Issue.record("Expected the stable file to exceed the byte limit")
        } catch let failure as LocalSourceInspectionFailure {
            #expect(failure.code == .limitExceeded)
        }
    }

    @Test("A read without an expected stamp keeps the original missing-input classification")
    func readWithoutExpectedStampPreservesV1Failure() throws {
        let fixture = try DirectoryFixture()
        defer { fixture.remove() }
        let directory = try fixture.inspectionDirectory()

        do {
            _ = try directory.read(
                components: ["Sources", "Missing.swift"], maximumBytes: 1_024
            )
            Issue.record("Expected the absent file to be rejected")
        } catch let failure as LocalSourceInspectionFailure {
            #expect(failure.code == .missingInput)
        }
    }
}

private struct DirectoryFixture {
    let base: URL
    let root: URL
    let sources: URL

    init() throws {
        base = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("pkglift-directory-observation-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Root", isDirectory: true)
        sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    }

    func write(_ relativePath: String, bytes: Data = Data("test\n".utf8)) throws {
        let destination = sources.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: destination)
    }

    func inspectionDirectory() throws -> InspectionDirectory {
        let path = try InspectionInputPath(root.path)
        return try InspectionDirectory(isAbsolute: path.isAbsolute, components: path.components)
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }
}
