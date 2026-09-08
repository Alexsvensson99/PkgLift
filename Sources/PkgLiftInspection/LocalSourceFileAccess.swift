import CryptoKit
import Darwin
import Foundation

/// No descriptors or private path strings cross the inspection result boundary.
final class InspectionDescriptor {
    let rawValue: Int32
    init(_ rawValue: Int32) { self.rawValue = rawValue }
    deinit { _ = close(rawValue) }
}

struct InspectionFileStamp: Equatable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let size: off_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    init(_ value: stat) {
        device = value.st_dev
        inode = value.st_ino
        mode = value.st_mode
        size = value.st_size
        modifiedSeconds = value.st_mtimespec.tv_sec
        modifiedNanoseconds = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec
        changedNanoseconds = value.st_ctimespec.tv_nsec
    }

    var isDirectory: Bool { mode & mode_t(S_IFMT) == mode_t(S_IFDIR) }
    var isRegular: Bool { mode & mode_t(S_IFMT) == mode_t(S_IFREG) }
    var isSymlink: Bool { mode & mode_t(S_IFMT) == mode_t(S_IFLNK) }

    func sameObject(as other: Self) -> Bool {
        device == other.device && inode == other.inode
            && (mode & mode_t(S_IFMT)) == (other.mode & mode_t(S_IFMT))
    }

    static func descriptor(_ descriptor: InspectionDescriptor) throws -> Self {
        var value = stat()
        guard fstat(descriptor.rawValue, &value) == 0 else { throw inspectionSystemFailure() }
        return Self(value)
    }

    static func child(_ name: String, of directory: InspectionDescriptor) throws -> Self {
        var value = stat()
        guard fstatat(directory.rawValue, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw inspectionSystemFailure()
        }
        return Self(value)
    }
}

struct InspectionInputPath {
    let isAbsolute: Bool
    let components: [String]

    init(_ input: String) throws {
        guard !input.isEmpty,
              !input.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw LocalSourceInspectionFailure(.invalidInputPath)
        }
        isAbsolute = input.hasPrefix("/")
        let pieces = input.split(separator: "/").map(String.init)
        guard !pieces.contains("..") else { throw LocalSourceInspectionFailure(.invalidInputPath) }
        components = pieces.filter { $0 != "." }
    }
}

private struct InspectionDirectoryWalk {
    let descriptor: InspectionDescriptor
    let identities: [InspectionFileStamp]

    init(anchor: InspectionDescriptor, components: [String]) throws {
        var current = anchor
        var identities: [InspectionFileStamp] = []
        for component in components {
            let before = try InspectionFileStamp.child(component, of: current)
            guard !before.isSymlink else { throw LocalSourceInspectionFailure(.symbolicLink) }
            guard before.isDirectory else { throw LocalSourceInspectionFailure(.nonRegularFile) }
            let raw = openat(current.rawValue, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard raw >= 0 else { throw inspectionSystemFailure() }
            let next = InspectionDescriptor(raw)
            let opened = try InspectionFileStamp.descriptor(next)
            guard before.sameObject(as: opened), opened.isDirectory else {
                throw LocalSourceInspectionFailure(.changedDuringRead)
            }
            identities.append(opened)
            current = next
        }
        descriptor = current
        self.identities = identities
    }
}

/// A stable anchor plus the identities of every traversed directory component.
/// Ancestor timestamps are intentionally excluded: unrelated /private/tmp activity
/// does not alter the identity of the user's chosen root.
final class InspectionDirectory {
    private let anchor: InspectionDescriptor
    private let components: [String]
    private let ancestry: [InspectionFileStamp]
    let descriptor: InspectionDescriptor
    private let initialStamp: InspectionFileStamp

    init(isAbsolute: Bool, components: [String]) throws {
        let raw = open(isAbsolute ? "/" : ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard raw >= 0 else { throw inspectionSystemFailure() }
        let anchor = InspectionDescriptor(raw)
        let walk = try InspectionDirectoryWalk(anchor: anchor, components: components)
        self.anchor = anchor
        self.components = components
        ancestry = walk.identities
        descriptor = walk.descriptor
        initialStamp = try InspectionFileStamp.descriptor(descriptor)
    }

    func validate() throws {
        do {
            let walk = try InspectionDirectoryWalk(anchor: anchor, components: components)
            let reopened = try InspectionFileStamp.descriptor(walk.descriptor)
            let retained = try InspectionFileStamp.descriptor(descriptor)
            guard Self.sameIdentities(ancestry, walk.identities),
                  initialStamp == reopened, initialStamp == retained else {
                throw LocalSourceInspectionFailure(.changedDuringRead)
            }
        } catch {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
    }

    struct Observation {
        let components: [String]
        let ancestry: [InspectionFileStamp]
        let stamp: InspectionFileStamp
        let byteCount: Int
        let contentSHA256: String
    }

    struct ReadResult {
        let observation: Observation
        let bytes: Data
    }

    func read(
        components: [String], maximumBytes: Int, captureBytes: Bool = false,
        afterChunk: (() -> Void)? = nil
    ) throws -> ReadResult {
        guard let name = components.last else { throw LocalSourceInspectionFailure(.invalidInputPath) }
        let parent = try InspectionDirectoryWalk(anchor: descriptor, components: Array(components.dropLast()))
        let before = try InspectionFileStamp.child(name, of: parent.descriptor)
        guard !before.isSymlink else { throw LocalSourceInspectionFailure(.symbolicLink) }
        guard before.isRegular else { throw LocalSourceInspectionFailure(.nonRegularFile) }
        guard before.size >= 0, before.size <= maximumBytes else {
            throw LocalSourceInspectionFailure(.limitExceeded)
        }
        // NONBLOCK prevents a raced-in FIFO from hanging open; fstat still enforces
        // regular-file type before any content read.
        let raw = openat(parent.descriptor.rawValue, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard raw >= 0 else { throw inspectionSystemFailure() }
        let file = InspectionDescriptor(raw)
        let opened = try InspectionFileStamp.descriptor(file)
        guard before == opened, opened.isRegular else {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
        var hasher = SHA256()
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var byteCount = 0
        var interruptedReads = 0
        while true {
            let count = buffer.withUnsafeMutableBytes { storage in
                Darwin.read(file.rawValue, storage.baseAddress, storage.count)
            }
            if count < 0 {
                if errno == EINTR, interruptedReads < 8 {
                    interruptedReads += 1
                    continue
                }
                throw inspectionSystemFailure()
            }
            if count == 0 { break }
            guard count <= maximumBytes - byteCount else {
                throw LocalSourceInspectionFailure(.limitExceeded)
            }
            byteCount += count
            let chunk = Data(buffer.prefix(count))
            hasher.update(data: chunk)
            if captureBytes { bytes.append(chunk) }
            afterChunk?()
        }
        let after = try InspectionFileStamp.descriptor(file)
        let bound = try InspectionFileStamp.child(name, of: parent.descriptor)
        guard opened == after, after.size == byteCount,
              after == bound else {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return ReadResult(
            observation: Observation(
                components: components, ancestry: parent.identities, stamp: after,
                byteCount: byteCount, contentSHA256: digest
            ),
            bytes: bytes
        )
    }

    func validate(_ observation: Observation, maximumBytes: Int) throws {
        do {
            let current = try read(components: observation.components, maximumBytes: maximumBytes).observation
            guard Self.sameIdentities(observation.ancestry, current.ancestry),
                  observation.stamp == current.stamp,
                  observation.byteCount == current.byteCount,
                  observation.contentSHA256 == current.contentSHA256 else {
                throw LocalSourceInspectionFailure(.changedDuringRead)
            }
        } catch {
            throw LocalSourceInspectionFailure(.changedDuringRead)
        }
    }

    private static func sameIdentities(_ lhs: [InspectionFileStamp], _ rhs: [InspectionFileStamp]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.sameObject(as: $1) }
    }
}

private func inspectionSystemFailure() -> LocalSourceInspectionFailure {
    switch errno {
    case ELOOP: LocalSourceInspectionFailure(.symbolicLink)
    case ENOENT: LocalSourceInspectionFailure(.missingInput)
    case ENOTDIR: LocalSourceInspectionFailure(.nonRegularFile)
    default: LocalSourceInspectionFailure(.unreadableInput)
    }
}
