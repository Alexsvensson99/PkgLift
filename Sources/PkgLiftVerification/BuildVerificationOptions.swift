import Foundation

/// Explicit xcodebuild settings used during build verification.
///
/// Values are passed as individual process arguments. They are never joined
/// into a shell command. The derived-data path is deliberately redacted from
/// summaries because it may contain a username or private directory layout.
public struct BuildVerificationOptions: Sendable, Equatable {
    public let configuration: String?
    public let destination: String?
    public let sdk: String?
    public let derivedDataPath: String?

    public init(
        configuration: String? = nil,
        destination: String? = nil,
        sdk: String? = nil,
        derivedDataPath: String? = nil
    ) {
        self.configuration = configuration
        self.destination = destination
        self.sdk = sdk
        self.derivedDataPath = derivedDataPath
    }

    public var isEmpty: Bool {
        configuration == nil
            && destination == nil
            && sdk == nil
            && derivedDataPath == nil
    }

    /// Returns a normalized copy or throws before xcodebuild is launched.
    public func validated() throws -> BuildVerificationOptions {
        BuildVerificationOptions(
            configuration: try Self.normalize(configuration, field: "configuration"),
            destination: try Self.normalize(destination, field: "destination"),
            sdk: try Self.normalize(sdk, field: "sdk"),
            derivedDataPath: try Self.normalize(derivedDataPath, field: "derived-data-path")
        )
    }

    /// Human-readable settings suitable for logs and JSON check detail.
    ///
    /// The path itself is never included.
    public var redactedSummary: String {
        [
            "configuration=\(configuration ?? "<xcode-default>")",
            "destination=\(destination ?? "<xcode-default>")",
            "sdk=\(sdk ?? "<xcode-default>")",
            "derivedDataPath=\(derivedDataPath == nil ? "<xcode-default>" : "<provided>")",
        ].joined(separator: ", ")
    }

    private static func normalize(_ value: String?, field: String) throws -> String? {
        guard let value else { return nil }

        if value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            throw BuildVerificationOptionsError.controlCharacter(field: field)
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw BuildVerificationOptionsError.empty(field: field)
        }
        return normalized
    }
}

public enum BuildVerificationOptionsError: LocalizedError, Sendable, Equatable {
    case empty(field: String)
    case controlCharacter(field: String)
    case schemeRequiredForWorkspaceResolution
    case schemeRequiredForDerivedDataResolution

    public var errorDescription: String? {
        switch self {
        case .empty(let field):
            return "Build verification option --\(field) cannot be empty."
        case .controlCharacter(let field):
            return "Build verification option --\(field) cannot contain control characters."
        case .schemeRequiredForWorkspaceResolution:
            return "Workspace package resolution requires an explicit scheme."
        case .schemeRequiredForDerivedDataResolution:
            return "Package resolution with a derived-data path requires an explicit scheme."
        }
    }
}
