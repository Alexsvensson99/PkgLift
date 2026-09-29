import Foundation

/// Keep the accepted project formats independent of XcodeProj reader upgrades.
/// Package visibility lets migration reject the format before touching Podfile,
/// without adding a public API or a case to a source-compatible public enum.
package enum XcodeProjectFormatGuard {
    package static func validate(at path: String) throws {
        let project = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        // Enumerate names rather than following file contents: a dangling link,
        // directory, or second definition with this extension must also refuse.
        let names = try FileManager.default.contentsOfDirectory(atPath: project.path)
        if names.contains(where: { $0.lowercased().hasSuffix(".xcproj") }) {
            throw UnsupportedXcodeProjectFormatError(projectPath: path)
        }
    }
}

struct UnsupportedXcodeProjectFormatError: LocalizedError, Sendable {
    let projectPath: String

    var errorDescription: String? {
        "Unsupported Xcode project format at path: \(projectPath). "
            + "PkgLift does not support project.xcproj; use a PBX project without .xcproj files."
    }
}
