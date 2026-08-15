import Foundation

/// Canonical comparison identity for remote package repositories.
/// URL scheme and host are case-insensitive; repository paths are preserved.
public enum RepositoryIdentity {
    public static func normalized(_ repositoryURL: String) -> String {
        var value = repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if value.lowercased().hasSuffix(".git") { value.removeLast(4) }

        if var components = URLComponents(string: value), components.scheme != nil {
            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            return components.string ?? value
        }

        // Preserve the path case in SCP-style Git URLs such as
        // git@host:Owner/Repository while normalizing the host portion.
        if let at = value.firstIndex(of: "@"),
           let colon = value[value.index(after: at)...].firstIndex(of: ":") {
            return value[..<colon].lowercased() + value[colon...]
        }

        return value
    }

    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }
}
