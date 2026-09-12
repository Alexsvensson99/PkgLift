/// Explicitly versioned local selection rules. Neither profile is migration evidence.
public enum LocalSourceSelectionMode: String, Sendable {
    case literalOnly = "literal-only"
    case flatSwiftGlobs = "flat-swift-globs"

    var schemaVersion: Int { self == .literalOnly ? 1 : 2 }
    var pathProfile: String { "ascii-relative-path/v\(schemaVersion)" }
    var providerProfile: String { "pkglift.local-source-inspection/v\(schemaVersion)" }
    var selectionProfile: String? {
        self == .literalOnly ? nil : "root-literals-and-flat-swift-globs/v1"
    }
}

enum InspectionSourcePath {
    static func validate(
        _ path: String, declarationIndex: Int, mode: LocalSourceSelectionMode = .literalOnly
    ) throws {
        guard path.utf8.count <= 512 else {
            throw LocalSourceInspectionFailure(.limitExceeded, declarationIndex: declarationIndex)
        }
        guard !path.isEmpty, !path.hasPrefix("/"), path.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || [UInt8(95), 46, 45, 47, 42, 63, 91, 93, 123, 125].contains($0)
                || (mode == .flatSwiftGlobs && $0 == 43)
        }) else { throw LocalSourceInspectionFailure(.invalidSourcePath, declarationIndex: declarationIndex) }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw LocalSourceInspectionFailure(.invalidSourcePath, declarationIndex: declarationIndex)
        }
    }

    static func containsPattern(_ path: String) -> Bool {
        path.contains(where: { "*?[]{}".contains($0) })
    }

    /// Called only after canonical declaration validation; parent components are literal.
    static func flatGlobDirectory(_ path: String) -> [String]? {
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 2, components.last == "*.swift",
              components.dropLast().allSatisfy({ !containsPattern($0) }) else { return nil }
        return Array(components.dropLast())
    }

    /// Inspect raw names before decoding so invalid UTF-8 cannot become a different path.
    static func matchesFlatSwiftName(_ bytes: [UInt8]) -> Bool {
        bytes.first != UInt8(46) && bytes.suffix(6).elementsEqual(Array(".swift".utf8))
    }

    static func matchedPath(directory: [String], nameBytes: [UInt8], declarationIndex: Int) throws -> String {
        guard nameBytes.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                || [UInt8(95), 46, 45, 43].contains($0)
        }) else { throw LocalSourceInspectionFailure(.invalidSourcePath, declarationIndex: declarationIndex) }
        let path = (directory + [String(decoding: nameBytes, as: UTF8.self)]).joined(separator: "/")
        try validate(path, declarationIndex: declarationIndex, mode: .flatSwiftGlobs)
        return path
    }
}
