// PkgLiftXcode/HeaderImportInspector.swift
// Bounded, read-only inspection of Objective-C header imports.

import Darwin
import Foundation
import PkgLiftCore

struct HeaderImportInspector {
    private static let maximumFileBytes = 1_024 * 1_024
    private static let maximumTotalBytes = 16 * 1_024 * 1_024
    private static let maximumFiles = 512
    private static let maximumDepth = 32

    func inspect(files: [URL], root: URL) -> TargetHeaderImportStatus {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        var state = State(root: canonicalRoot)
        for file in files {
            if let relative = state.relativePath(for: file) {
                state.inspect(relative, depth: 0)
            } else {
                state.incomplete = true
            }
        }
        return state.requiresReview ? .requiresReview : state.incomplete ? .incomplete : .clear
    }

    private final class State {
        let root: URL
        var visited = Set<String>()
        var totalBytes = 0
        var requiresReview = false
        var incomplete = false

        init(root: URL) { self.root = root }

        func relativePath(for url: URL) -> [String]? {
            guard !url.path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return nil }
            let candidate = url.standardizedFileURL
            guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
            let relative = String(candidate.path.dropFirst(root.path.count)).split(separator: "/").map(String.init)
            guard !relative.isEmpty, !relative.contains(".."), !relative.contains(".") else { return nil }
            return relative
        }

        func inspect(_ relative: [String], depth: Int) {
            guard depth <= HeaderImportInspector.maximumDepth else { incomplete = true; return }
            let key = relative.joined(separator: "/")
            guard visited.insert(key).inserted else { return }
            guard visited.count <= HeaderImportInspector.maximumFiles,
                  let bytes = readRegularFile(relative),
                  !bytes.starts(with: [0xEF, 0xBB, 0xBF]),
                  bytes.count <= HeaderImportInspector.maximumFileBytes else { incomplete = true; return }
            guard let source = String(data: bytes, encoding: .utf8),
                  let directives = directives(in: source) else { incomplete = true; return }
            for directive in directives {
                switch directive {
                case .flatAngle:
                    requiresReview = true
                case .qualifiedAngle:
                    continue
                case .quoted(let target):
                    let parent = Array(relative.dropLast())
                    let components = parent + target.split(separator: "/").map(String.init)
                    guard !target.hasPrefix("/"), !components.contains(".."), !components.contains(".") else {
                        incomplete = true
                        continue
                    }
                    switch entryKind(components) {
                    case .missing:
                        requiresReview = true
                    case .unsafe:
                        incomplete = true
                    case .regular:
                        inspect(components, depth: depth + 1)
                    }
                }
            }
        }

        private enum Directive {
            case flatAngle
            case qualifiedAngle
            case quoted(String)
        }

        private enum EntryKind { case missing, regular, unsafe }

        private func entryKind(_ components: [String]) -> EntryKind {
            var path = root.path
            for (offset, component) in components.enumerated() {
                path += "/" + component
                var info = stat()
                guard lstat(path, &info) == 0 else { return errno == ENOENT ? .missing : .unsafe }
                if (info.st_mode & S_IFMT) == S_IFLNK { return .unsafe }
                if offset < components.count - 1 {
                    guard (info.st_mode & S_IFMT) == S_IFDIR else { return .unsafe }
                } else {
                    return (info.st_mode & S_IFMT) == S_IFREG ? .regular : .unsafe
                }
            }
            return .unsafe
        }

        private func directives(in source: String) -> [Directive]? {
            guard !source.hasPrefix("\u{FEFF}"), !source.contains("??"), !source.contains("%:"), !source.contains("R\"") else { return nil }
            let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let joined = normalized.replacingOccurrences(of: "\\\n", with: "")
            guard let withoutComments = stripComments(joined) else { return nil }
            let headerUnitPattern = #"(?m)^(?![ \t]*#).*?\b(?:export[ \t]+)?import[ \t]*[<\"]"#
            guard withoutComments.range(of: headerUnitPattern, options: .regularExpression) == nil else { return nil }
            var result: [Directive] = []
            for line in withoutComments.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("#") else { continue }
                let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                guard rest.hasPrefix("import") || rest.hasPrefix("include") else { continue }
                let keyword = rest.hasPrefix("import") ? "import" : "include"
                let afterKeyword = rest.dropFirst(keyword.count)
                guard afterKeyword.isEmpty || afterKeyword.first?.isWhitespace == true
                        || afterKeyword.first == "<" || afterKeyword.first == "\"" else { return nil }
                let operand = afterKeyword.trimmingCharacters(in: .whitespaces)
                if operand.hasPrefix("<") && operand.hasSuffix(">"), operand.dropFirst().dropLast().allSatisfy({ !$0.isWhitespace }) {
                    let name = String(operand.dropFirst().dropLast())
                    let components = name.split(separator: "/", omittingEmptySubsequences: false)
                    guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains("<"), !name.contains(">"),
                          !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                          !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
                    result.append(name.contains("/") ? .qualifiedAngle : .flatAngle)
                } else if operand.hasPrefix("\"") && operand.hasSuffix("\""), !operand.dropFirst().dropLast().contains("\"") {
                    let name = String(operand.dropFirst().dropLast())
                    let components = name.split(separator: "/", omittingEmptySubsequences: false)
                    guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"),
                          !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                          !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
                    result.append(.quoted(name))
                } else {
                    return nil
                }
            }
            return result
        }

        private func stripComments(_ source: String) -> String? {
            var output = "", index = source.startIndex, block = false, string: Character? = nil
            while index < source.endIndex {
                let character = source[index], next = source.index(after: index)
                let following = next < source.endIndex ? source[next] : "\0"
                if block {
                    if character == "*" && following == "/" { block = false; index = source.index(after: next); continue }
                    if character == "\n" { output.append(character) }
                    index = next; continue
                }
                if let quote = string {
                    output.append(character)
                    if character == "\\" && next < source.endIndex { output.append(source[next]); index = source.index(after: next); continue }
                    if character == quote { string = nil }
                    index = next; continue
                }
                if character == "/" && following == "*" { output.append(" "); block = true; index = source.index(after: next); continue }
                if character == "/" && following == "/" {
                    output.append(" ")
                    while index < source.endIndex && source[index] != "\n" { index = source.index(after: index) }
                    continue
                }
                if character == "\"" || character == "'" { string = character }
                output.append(character); index = next
            }
            return block || string != nil ? nil : output
        }

        private func readRegularFile(_ components: [String]) -> Data? {
            let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard rootFD >= 0 else { return nil }
            defer { close(rootFD) }
            var directoryFD = rootFD
            var ownedFDs: [Int32] = []
            defer { ownedFDs.forEach { close($0) } }
            for component in components.dropLast() {
                guard !component.isEmpty else { return nil }
                let next = openat(directoryFD, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard next >= 0 else { return nil }
                ownedFDs.append(next); directoryFD = next
            }
            guard let name = components.last else { return nil }
            let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { return nil }
            defer { close(fd) }
            var before = stat()
            guard fstat(fd, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG,
                  before.st_size >= 0, before.st_size <= HeaderImportInspector.maximumFileBytes,
                  before.st_size <= HeaderImportInspector.maximumTotalBytes - totalBytes else { return nil }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = read(fd, &buffer, buffer.count)
                if count == 0 {
                    var after = stat()
                    guard fstat(fd, &after) == 0, after.st_dev == before.st_dev, after.st_ino == before.st_ino,
                          after.st_size == before.st_size, after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
                          after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec, after.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec,
                          after.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec else { return nil }
                    return data
                }
                guard count > 0 else { return nil }
                totalBytes += count
                guard totalBytes <= HeaderImportInspector.maximumTotalBytes else { return nil }
                data.append(buffer, count: count)
                guard data.count <= HeaderImportInspector.maximumFileBytes else { return nil }
            }
        }
    }
}
