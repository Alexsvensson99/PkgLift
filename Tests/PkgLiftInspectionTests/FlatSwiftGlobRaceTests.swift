import Darwin
import Foundation
import Testing
@testable import PkgLiftInspection

@Suite("Flat Swift glob filesystem safety", .serialized)
struct FlatSwiftGlobRaceTests {
    @Test("Changed selection during either directory pass never produces an inventory", arguments: [1, 2])
    func membershipDuringEnumeration(pass: Int) throws {
        let fixture = try GlobRaceFixture()
        defer { fixture.remove() }
        let mutation = MutationFlag()
        let inspector = LocalSourceInspector { event in
            guard event == .afterDirectoryEntry(declarationIndex: 0, pass: pass) else { return }
            mutation.withLock { changed in
                guard !changed else { return }
                do {
                    try Data().write(to: fixture.sources.appendingPathComponent("New.swift"))
                    changed = true
                } catch { Issue.record("Fixture mutation failed") }
            }
        }
        refuse(fixture.inspect(with: inspector), code: .changedDuringRead)
        #expect(mutation.withLock { $0 })
    }

    @Test("Membership, identity and unselected-entry changes between passes fail closed", arguments: [
        "add", "delete", "rename", "replaceSameBytes", "modifyUnmatched", "replaceDirectory", "replaceWithSymlink"
    ])
    func mutationBetweenPasses(kind: String) throws {
        let fixture = try GlobRaceFixture()
        defer { fixture.remove() }
        let mutation = MutationFlag()
        let inspector = LocalSourceInspector { event in
            guard event == .afterDirectoryEnumeration(declarationIndex: 0, pass: 1) else { return }
            do {
                switch kind {
                case "add":
                    try Data().write(to: fixture.sources.appendingPathComponent("New.swift"))
                case "delete":
                    try FileManager.default.removeItem(at: fixture.source)
                case "rename":
                    try FileManager.default.moveItem(at: fixture.source, to: fixture.sources.appendingPathComponent("Renamed.swift"))
                case "replaceSameBytes":
                    let original = fixture.base.appendingPathComponent("Original.swift")
                    try FileManager.default.moveItem(at: fixture.source, to: original)
                    try Data("struct A {}\n".utf8).write(to: fixture.source)
                case "modifyUnmatched":
                    try Data("changed\n".utf8).write(to: fixture.sources.appendingPathComponent("Notes.txt"))
                case "replaceDirectory":
                    try FileManager.default.moveItem(at: fixture.sources, to: fixture.base.appendingPathComponent("OriginalSources"))
                    try FileManager.default.createDirectory(at: fixture.sources, withIntermediateDirectories: false)
                    try Data("struct A {}\n".utf8).write(to: fixture.source)
                case "replaceWithSymlink":
                    try FileManager.default.moveItem(at: fixture.source, to: fixture.base.appendingPathComponent("Original.swift"))
                    try FileManager.default.createSymbolicLink(at: fixture.source, withDestinationURL: fixture.base.appendingPathComponent("Original.swift"))
                default: Issue.record("Unknown test mutation")
                }
                mutation.withLock { $0 = true }
            } catch { Issue.record("Fixture mutation failed") }
        }
        let report = fixture.inspect(with: inspector)
        // The initial directory stamp binds even entries that disappear or
        // change type before their first content read.
        #expect(report.status == .unavailable)
        #expect(report.sources.isEmpty)
        #expect(report.inventorySHA256 == nil)
        #expect(report.schemaVersion == 2)
        #expect(mutation.withLock { $0 })
        #expect(report.reasons.contains { $0.code == .changedDuringRead })
    }

    @Test("A change after the second directory pass is caught by final binding validation")
    func mutationAfterSecondPass() throws {
        let fixture = try GlobRaceFixture()
        defer { fixture.remove() }
        let mutation = MutationFlag()
        let inspector = LocalSourceInspector { event in
            guard event == .afterDirectoryEnumeration(declarationIndex: 0, pass: 2) else { return }
            do {
                try Data().write(to: fixture.sources.appendingPathComponent("New.swift"))
                mutation.withLock { $0 = true }
            } catch { Issue.record("Fixture mutation failed") }
        }
        refuse(fixture.inspect(with: inspector), code: .changedDuringRead)
        #expect(mutation.withLock { $0 })
    }

    @Test("Matching unsafe types and non-ASCII names are refused", arguments: ["symlink", "directory", "fifo", "nonASCII"])
    func unsafeMatchingEntry(kind: String) throws {
        let fixture = try GlobRaceFixture()
        defer { fixture.remove() }
        let entry = fixture.sources.appendingPathComponent(kind == "nonASCII" ? "é.swift" : "Unsafe.swift")
        switch kind {
        case "symlink":
            try FileManager.default.createSymbolicLink(at: entry, withDestinationURL: fixture.source)
        case "directory":
            try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: false)
        case "fifo":
            #expect(mkfifo(entry.path, mode_t(0o600)) == 0)
        case "nonASCII":
            try Data().write(to: entry)
        default: Issue.record("Unknown fixture kind")
        }
        let code: LocalSourceInspectionReport.Reason.Code = kind == "symlink" ? .symbolicLink
            : kind == "nonASCII" ? .invalidSourcePath : .nonRegularFile
        refuse(fixture.inspect(), code: code)
    }

    @Test("Nonmatching links, special files and directories are counted without being followed")
    func unmatchedEntriesAreNotRead() throws {
        let fixture = try GlobRaceFixture()
        defer { fixture.remove() }
        try FileManager.default.createSymbolicLink(
            atPath: fixture.sources.appendingPathComponent("Outside").path,
            withDestinationPath: "/does-not-exist/private"
        )
        #expect(mkfifo(fixture.sources.appendingPathComponent("Pipe.txt").path, mode_t(0o600)) == 0)
        try FileManager.default.createDirectory(at: fixture.sources.appendingPathComponent("Nested"), withIntermediateDirectories: false)
        try Data().write(to: fixture.sources.appendingPathComponent("Nested/Hidden.swift"))
        let report = fixture.inspect()
        #expect(report.status == .verifiedObservedBytes)
        #expect(report.sources.count == 1)
    }

    @Test("A glob directory or ancestor cannot be a symlink", arguments: ["Sources", "Parent"])
    func linkedGlobDirectory(component: String) throws {
        let fixture = try GlobRaceFixture()
        defer { fixture.remove() }
        let original = fixture.base.appendingPathComponent("OriginalSources")
        try FileManager.default.moveItem(at: fixture.sources, to: original)
        if component == "Sources" {
            try FileManager.default.createSymbolicLink(at: fixture.sources, withDestinationURL: original)
        } else {
            try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("Parent"), withDestinationURL: fixture.base)
            try fixture.writePodspec(["Parent/OriginalSources/*.swift"])
        }
        refuse(fixture.inspect(), code: .symbolicLink)
    }

    @Test("V2 strictly bounds per-file and cumulative source bytes", arguments: ["perFile", "total", "exactTotal"])
    func byteLimits(kind: String) throws {
        let fixture = try GlobRaceFixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.source)
        let count = kind == "perFile" ? 1 : kind == "total" ? 5 : 4
        for index in 0..<count {
            let path = fixture.sources.appendingPathComponent("File\(index).swift")
            #expect(FileManager.default.createFile(atPath: path.path, contents: nil))
            let handle = try FileHandle(forWritingTo: path)
            let size = kind == "perFile" ? 16 * 1_024 * 1_024 + 1 : index == 4 ? 1 : 16 * 1_024 * 1_024
            try handle.truncate(atOffset: UInt64(size))
            try handle.close()
        }
        let report = fixture.inspect()
        if kind == "exactTotal" {
            let totalBytes: Int = report.sources.reduce(0) { $0 + $1.byteCount }
            let expectedBytes: Int = 64 * 1_024 * 1_024
            #expect(report.status == .verifiedObservedBytes)
            #expect(totalBytes == expectedBytes)
        } else {
            refuse(report, code: .limitExceeded)
        }
    }

    @Test("Growing sources in v2 cannot exceed a read-pass budget", arguments: ["initial", "validation"])
    func growingSource(kind: String) throws {
        let fixture = try GlobRaceFixture()
        defer { fixture.remove() }
        let handle = try FileHandle(forWritingTo: fixture.source)
        try handle.truncate(atOffset: 65_536)
        try handle.close()
        let mutation = MutationFlag()
        let inspector = LocalSourceInspector { event in
            let trigger: LocalSourceInspectionEvent = kind == "initial"
                ? .afterSourceChunk(0) : .afterDirectoryEnumeration(declarationIndex: 0, pass: 2)
            guard event == trigger else { return }
            mutation.withLock { changed in
                guard !changed else { return }
                do {
                    let writer = try FileHandle(forWritingTo: fixture.source)
                    try writer.truncate(atOffset: UInt64(16 * 1_024 * 1_024 + 1))
                    try writer.close()
                    changed = true
                } catch { Issue.record("Fixture growth failed") }
            }
        }
        refuse(fixture.inspect(with: inspector), code: .changedDuringRead)
        #expect(mutation.withLock { $0 })
    }

    @Test("An enumeration that cannot inspect child metadata is unavailable")
    func enumerationPermissionFailure() throws {
        let fixture = try GlobRaceFixture()
        defer { fixture.remove() }
        #expect(chmod(fixture.sources.path, mode_t(0o400)) == 0)
        defer { _ = chmod(fixture.sources.path, mode_t(0o700)) }
        refuse(fixture.inspect(), code: .unreadableInput)
    }

    @Test("Raw invalid UTF-8 cannot be repaired into an accepted matching path")
    func invalidNameBytes() {
        let bytes: [UInt8] = [0xff] + Array(".swift".utf8)
        #expect(InspectionSourcePath.matchesFlatSwiftName(bytes))
        #expect(throws: LocalSourceInspectionFailure.self) {
            try InspectionSourcePath.matchedPath(directory: ["Sources"], nameBytes: bytes, declarationIndex: 0)
        }
    }

    private func refuse(_ report: LocalSourceInspectionReport, code: LocalSourceInspectionReport.Reason.Code) {
        #expect(report.status == .unavailable)
        #expect(report.exitCode == 1)
        #expect(report.schemaVersion == 2)
        #expect(report.reasons.contains { $0.code == code })
        #expect(report.sources.isEmpty)
        #expect(report.inventorySHA256 == nil)
    }
}

private struct GlobRaceFixture: Sendable {
    let base: URL
    let root: URL
    let sources: URL
    let source: URL
    let podspec: URL

    init() throws {
        base = URL(fileURLWithPath: "/private/tmp/pkglift-flat-race-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("Root")
        sources = root.appendingPathComponent("Sources")
        source = sources.appendingPathComponent("A.swift")
        podspec = base.appendingPathComponent("input.json")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("struct A {}\n".utf8).write(to: source)
        try Data("initial\n".utf8).write(to: sources.appendingPathComponent("Notes.txt"))
        try writePodspec(["Sources/*.swift"])
    }

    func writePodspec(_ paths: [String]) throws {
        try JSONSerialization.data(withJSONObject: ["name": "Example", "version": "1", "source_files": paths], options: [.sortedKeys]).write(to: podspec)
    }

    func inspect(with inspector: LocalSourceInspector = LocalSourceInspector()) -> LocalSourceInspectionReport {
        inspector.inspect(podspecPath: podspec.path, sourceRoot: root.path, sourceSelection: .flatSwiftGlobs)
    }

    func remove() { try? FileManager.default.removeItem(at: base) }
}

/// The test observer is Sendable; all mutable state is protected by this lock.
private final class MutationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func withLock<T>(_ body: (inout Bool) -> T) -> T {
        lock.withLock { body(&value) }
    }
}
