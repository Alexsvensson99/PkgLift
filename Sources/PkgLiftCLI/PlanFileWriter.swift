import Darwin
import Foundation

/// The saved plan has one fixed destination. Keep all mutations relative to
/// retained, no-follow directory descriptors rather than reopening pathnames.
/// Binding checks detect observed renames; this is not a filesystem transaction
/// against another process with authority to move the opened directories.
final class PlanFileWriter {
    private let bindings: [DirectoryBinding]
    private let directory: Descriptor

    init(canonicalRoot: String) throws {
        guard canonicalRoot.hasPrefix("/"), !canonicalRoot.utf8.contains(0) else {
            throw PlanWriteError.unsafeLocation
        }
        // Foundation may retain the system /var alias even after
        // resolvingSymlinksInPath(). Resolve the selected root with POSIX
        // semantics before walking it; never resolve the .pkglift child.
        guard let resolved = realpath(canonicalRoot, nil) else {
            throw PlanWriteError.system("resolve project root", errno)
        }
        defer { free(resolved) }
        let components = String(cString: resolved).split(separator: "/").map(String.init)
        guard !components.contains(".."), !components.contains(".") else {
            throw PlanWriteError.unsafeLocation
        }
        let anchor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard anchor >= 0 else { throw PlanWriteError.system("open project root", errno) }
        var current = Descriptor(anchor)
        var bindings: [DirectoryBinding] = []
        for name in components {
            let binding = try DirectoryBinding(parent: current, name: name)
            bindings.append(binding)
            current = binding.child
        }
        for binding in bindings { try binding.validate() }
        if mkdirat(current.rawValue, ".pkglift", mode_t(0o700)) != 0, errno != EEXIST {
            throw PlanWriteError.system("create plan directory", errno)
        }
        let state = try DirectoryBinding(parent: current, name: ".pkglift")
        bindings.append(state)
        self.bindings = bindings
        directory = state.child
        try validateBindings()
    }

    /// Staging and publication are separate so the final binding checks also
    /// cover changes that occur after the bytes have been written.
    func stage(_ data: Data) throws -> StagedPlan {
        try validateBindings()
        let destination = try destinationStamp()
        let name = ".plan-\(UUID().uuidString).tmp"
        let raw = openat(directory.rawValue, name,
                         O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard raw >= 0 else { throw PlanWriteError.system("create temporary plan", errno) }
        let staged = StagedPlan(writer: self, descriptor: Descriptor(raw), name: name,
                                destination: destination)
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var written = 0
            var interruptions = 0
            while written < bytes.count {
                let count = Darwin.write(raw, base.advanced(by: written), bytes.count - written)
                if count < 0, errno == EINTR, interruptions < 8 {
                    interruptions += 1
                    continue
                }
                guard count > 0 else { throw PlanWriteError.system("write temporary plan", count == 0 ? EIO : errno) }
                written += count
            }
        }
        guard fsync(raw) == 0 else { throw PlanWriteError.system("synchronize temporary plan", errno) }
        staged.writtenStamp = try Stamp.descriptor(staged.descriptor)
        return staged
    }

    private func validateBindings() throws {
        for binding in bindings { try binding.validate() }
    }

    private func destinationStamp() throws -> Stamp? {
        let stamp = try Stamp.child("plan.json", of: directory)
        guard stamp == nil || stamp?.isRegular == true else { throw PlanWriteError.unsafeLocation }
        return stamp
    }

    final class StagedPlan {
        private let writer: PlanFileWriter
        fileprivate let descriptor: Descriptor
        private let name: String
        private let destination: Stamp?
        fileprivate var writtenStamp: Stamp?
        private var published = false

        fileprivate init(writer: PlanFileWriter, descriptor: Descriptor, name: String, destination: Stamp?) {
            self.writer = writer
            self.descriptor = descriptor
            self.name = name
            self.destination = destination
        }

        func publish() throws {
            guard !published, let writtenStamp else { throw PlanWriteError.changedBinding }
            try writer.validateBindings()
            guard try writer.destinationStamp() == destination,
                  try Stamp.descriptor(descriptor) == writtenStamp,
                  try Stamp.child(name, of: writer.directory) == writtenStamp else {
                throw PlanWriteError.changedBinding
            }
            // renameat replaces the directory entry; it never opens/follows an
            // existing plan.json symlink or writes into its hard-linked inode.
            guard renameat(writer.directory.rawValue, name, writer.directory.rawValue, "plan.json") == 0 else {
                throw PlanWriteError.system("publish plan", errno)
            }
            published = true
        }

        deinit {
            // Failure cleanup must not remove an entry substituted by another
            // actor. Keep cleanup relative to our original directory as well.
            if !published,
               let retained = try? Stamp.descriptor(descriptor),
               let current = try? Stamp.child(name, of: writer.directory),
               retained.sameObject(as: current) {
                _ = unlinkat(writer.directory.rawValue, name, 0)
            }
        }
    }

    fileprivate final class Descriptor {
        let rawValue: Int32
        init(_ rawValue: Int32) { self.rawValue = rawValue }
        deinit { _ = close(rawValue) }
    }

    private struct DirectoryBinding {
        let parent: Descriptor
        let name: String
        let child: Descriptor
        let identity: Stamp

        init(parent: Descriptor, name: String) throws {
            guard let before = try Stamp.child(name, of: parent), before.isDirectory else {
                throw PlanWriteError.unsafeLocation
            }
            let raw = openat(parent.rawValue, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard raw >= 0 else { throw PlanWriteError.system("open plan directory", errno) }
            let child = Descriptor(raw)
            let opened = try Stamp.descriptor(child)
            guard before.sameObject(as: opened), opened.isDirectory else { throw PlanWriteError.changedBinding }
            self.parent = parent
            self.name = name
            self.child = child
            identity = opened
        }

        func validate() throws {
            guard let current = try Stamp.child(name, of: parent),
                  identity.sameObject(as: current),
                  try identity.sameObject(as: Stamp.descriptor(child)) else {
                throw PlanWriteError.changedBinding
            }
        }
    }

    fileprivate struct Stamp: Equatable {
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

        func sameObject(as other: Self) -> Bool {
            device == other.device && inode == other.inode
                && mode & mode_t(S_IFMT) == other.mode & mode_t(S_IFMT)
        }

        static func descriptor(_ descriptor: Descriptor) throws -> Self {
            var value = stat()
            guard fstat(descriptor.rawValue, &value) == 0 else { throw PlanWriteError.system("inspect plan file", errno) }
            return Self(value)
        }

        static func child(_ name: String, of directory: Descriptor) throws -> Self? {
            var value = stat()
            if fstatat(directory.rawValue, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
                if errno == ENOENT { return nil }
                throw PlanWriteError.system("inspect plan location", errno)
            }
            return Self(value)
        }
    }
}

enum PlanWriteError: LocalizedError, Equatable {
    case unsafeLocation
    case changedBinding
    case system(String, Int32)

    var errorDescription: String? {
        switch self {
        case .unsafeLocation:
            return "Cannot save plan: project/state directories must be real directories and plan.json must be absent or a regular file."
        case .changedBinding:
            return "Cannot save plan: its filesystem location changed during generation. Run plan again in a stable project."
        case .system(let operation, let code):
            return "Cannot save plan: failed to \(operation) (POSIX error \(code))."
        }
    }
}
