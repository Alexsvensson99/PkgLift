import Foundation

/// Produces a shareable JSON representation without changing the source data.
public struct PortableJSON: Sendable {
    public static let version = 1
    public static let redactedPath = "<redacted-path>"

    public init() {}

    /// Returns the original bytes unless portable output was explicitly selected.
    public func output(from data: Data, portable: Bool) throws -> Data {
        guard portable else { return data }
        return try render(data)
    }

    public func render(_ data: Data) throws -> Data {
        let decoded: Any
        do {
            decoded = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw PortableJSONError.invalidJSON
        }

        guard var root = sanitize(decoded, pathContext: false) as? [String: Any] else {
            throw PortableJSONError.rootMustBeObject
        }
        root["portableOutput"] = ["version": Self.version]

        guard JSONSerialization.isValidJSONObject(root) else {
            throw PortableJSONError.invalidJSON
        }
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func sanitize(_ value: Any, pathContext: Bool) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, element in
                let childPathContext = pathContext || Self.isPathKey(element.key)
                result[element.key] = sanitize(
                    element.value,
                    pathContext: childPathContext
                )
            }
        }
        if let array = value as? [Any] {
            return array.map { sanitize($0, pathContext: pathContext) }
        }
        if let string = value as? String {
            return Self.sanitize(string, pathContext: pathContext)
        }
        return value
    }

    private static func sanitize(_ value: String, pathContext: Bool) -> String {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return value }

        if candidate.hasPrefix("<"), candidate.hasSuffix(">") {
            return value
        }
        if candidate.lowercased().hasPrefix("file:") {
            return "file://\(redactedPath)"
        }
        if isExplicitLocalPath(candidate) || (pathContext && isPathValue(candidate)) {
            return redactedPath
        }
        if let sanitizedSCP = sanitizedSCPURL(candidate) {
            return sanitizedSCP
        }
        if var components = URLComponents(string: candidate), components.scheme != nil {
            components.user = nil
            components.password = nil
            components.query = nil
            components.fragment = nil
            return components.string ?? value
        }
        return value
    }

    private static func isPathKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("path")
            || normalized == "directory"
            || normalized == "root"
    }

    private static func isPathValue(_ value: String) -> Bool {
        !value.contains("\n") && !value.contains("\r")
    }

    private static func isExplicitLocalPath(_ value: String) -> Bool {
        if value.hasPrefix("/") || value.hasPrefix("\\\\") {
            return true
        }
        if value.hasPrefix("~/") || value.hasPrefix("~\\") {
            return true
        }
        if value.hasPrefix("./") || value.hasPrefix("../")
            || value.hasPrefix(".\\") || value.hasPrefix("..\\") {
            return true
        }

        let characters = Array(value)
        if characters.count >= 3,
           characters[0].isLetter,
           characters[1] == ":",
           characters[2] == "/" || characters[2] == "\\" {
            return true
        }

        guard value.hasPrefix("~"),
              let separator = value.firstIndex(where: { $0 == "/" || $0 == "\\" }) else {
            return false
        }
        return separator > value.startIndex
    }

    private static func sanitizedSCPURL(_ value: String) -> String? {
        guard !value.contains("://"),
              !value.contains(where: { $0.isWhitespace }),
              let at = value.firstIndex(of: "@"),
              let colon = value[at...].firstIndex(of: ":") else {
            return nil
        }

        let user = String(value[..<at])
        let host = String(value[value.index(after: at)..<colon])
        var path = String(value[value.index(after: colon)...])
        guard !user.isEmpty,
              !host.isEmpty,
              !path.isEmpty,
              user.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }),
              host.allSatisfy({ $0.isLetter || $0.isNumber || ".-".contains($0) }),
              path.contains("/") || path.hasSuffix(".git") else {
            return nil
        }

        if let sensitiveSuffix = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = String(path[..<sensitiveSuffix])
        }
        guard !path.isEmpty else { return nil }
        return "ssh://\(host)/\(path)"
    }
}

public enum PortableJSONError: LocalizedError, Sendable, Equatable {
    case invalidJSON
    case rootMustBeObject

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "Portable JSON output requires valid JSON input."
        case .rootMustBeObject:
            "Portable JSON output requires a top-level JSON object."
        }
    }
}
