import Foundation

public enum GitRepositorySyntax: String, Sendable, Codable, CaseIterable, Hashable {
    case https
    case ssh
    case scp
}

public enum GitRepositoryEvidenceStatus: String, Sendable, Codable, CaseIterable, Hashable {
    case supported
    case credentialBearing
    case ambiguousRepository
    case unsupportedURL
}

/// Canonical comparison identity for a repository at one transport boundary.
///
/// HTTPS identities intentionally remain distinct from SSH identities. SSH URLs
/// and SCP-like syntax both canonicalize to the same `ssh://host/path` identity.
public struct CanonicalRepositoryIdentity: Sendable, Codable, Hashable {
    public let value: String

    fileprivate init(validatedValue: String) {
        self.value = validatedValue
    }

    private enum CodingKeys: String, CodingKey {
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(String.self, forKey: .value)
        guard GitRepositoryCanonicalizer.isCanonicalIdentity(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Repository identity is not in canonical safe form."
            )
        }
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
    }
}

/// A sanitized repository observation. The original literal is deliberately not
/// retained, even when it contains credentials, query data, or a fragment.
public struct GitRepositoryEvidence: Sendable, Codable, Hashable {
    public static let redactedDisplayURL = "<redacted-url>"

    public let identity: CanonicalRepositoryIdentity?
    public let displayURL: String
    public let syntax: GitRepositorySyntax?
    public let containedCredentialMaterial: Bool
    public let status: GitRepositoryEvidenceStatus

    fileprivate init(
        identity: CanonicalRepositoryIdentity?,
        displayURL: String,
        syntax: GitRepositorySyntax?,
        containedCredentialMaterial: Bool,
        status: GitRepositoryEvidenceStatus
    ) {
        self.identity = identity
        self.displayURL = displayURL
        self.syntax = syntax
        self.containedCredentialMaterial = containedCredentialMaterial
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case identity
        case displayURL
        case syntax
        case containedCredentialMaterial
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try container.decodeIfPresent(CanonicalRepositoryIdentity.self, forKey: .identity)
        let displayURL = try container.decode(String.self, forKey: .displayURL)
        let syntax = try container.decodeIfPresent(GitRepositorySyntax.self, forKey: .syntax)
        let containedCredentialMaterial = try container.decode(
            Bool.self,
            forKey: .containedCredentialMaterial
        )
        let status = try container.decode(GitRepositoryEvidenceStatus.self, forKey: .status)

        guard Self.isValidCombination(
            identity: identity,
            displayURL: displayURL,
            syntax: syntax,
            containedCredentialMaterial: containedCredentialMaterial,
            status: status
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Repository evidence fields are inconsistent or unsafe."
            )
        }

        self.init(
            identity: identity,
            displayURL: displayURL,
            syntax: syntax,
            containedCredentialMaterial: containedCredentialMaterial,
            status: status
        )
    }

    private static func isValidCombination(
        identity: CanonicalRepositoryIdentity?,
        displayURL: String,
        syntax: GitRepositorySyntax?,
        containedCredentialMaterial: Bool,
        status: GitRepositoryEvidenceStatus
    ) -> Bool {
        guard let identity else {
            return identity == nil
                && displayURL == redactedDisplayURL
                && syntax == nil
                && status == .unsupportedURL
        }

        guard displayURL == identity.value,
              let syntax,
              syntaxMatchesIdentity(syntax, identity: identity) else {
            return false
        }
        guard let canonicalStatus = GitRepositoryCanonicalizer.canonicalIdentityStatus(
            identity.value
        ) else {
            return false
        }
        let expectedStatus: GitRepositoryEvidenceStatus = containedCredentialMaterial
            ? .credentialBearing
            : canonicalStatus
        return status == expectedStatus
    }

    private static func syntaxMatchesIdentity(
        _ syntax: GitRepositorySyntax,
        identity: CanonicalRepositoryIdentity
    ) -> Bool {
        switch syntax {
        case .https:
            identity.value.hasPrefix("https://")
        case .ssh, .scp:
            identity.value.hasPrefix("ssh://")
        }
    }
}

/// Pure, network-free canonicalization at the untrusted URL boundary.
public enum GitRepositoryCanonicalizer: Sendable {
    private static let rejectedPercentEscapes = [
        "%2f", "%5c", "%3a", "%40", "%3f", "%23", "%2e",
    ]

    public static func evidence(for literal: String) -> GitRepositoryEvidence {
        let trimmed = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == literal,
              !containsUnsafeScalar(trimmed),
              !containsRejectedPercentEscape(trimmed) else {
            return unsupportedEvidence(credentialBearing: appearsCredentialBearing(trimmed))
        }

        if trimmed.contains("://") {
            return canonicalizeURL(trimmed)
        }
        return canonicalizeSCP(trimmed)
    }

    fileprivate static func isCanonicalIdentity(_ value: String) -> Bool {
        canonicalIdentityStatus(value) != nil
    }

    /// Canonical identities are an internal comparison representation. In
    /// particular, `ssh://host/path` is emitted only after an input explicitly
    /// proved the structural `git` user; accepting that identity for decoding
    /// must not make a user-less SSH input supported at the parser boundary.
    fileprivate static func canonicalIdentityStatus(
        _ value: String
    ) -> GitRepositoryEvidenceStatus? {
        guard !containsUnsafeScalar(value),
              !containsRejectedPercentEscape(value),
              let components = URLComponents(string: value),
              let scheme = components.scheme,
              scheme == "https" || scheme == "ssh",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.port == nil,
              let rawHost = components.host,
              isSafeHost(rawHost),
              components.percentEncodedPath.hasPrefix("/") else {
            return nil
        }
        let pathLiteral = String(components.percentEncodedPath.dropFirst())
        guard let path = canonicalRepositoryPath(pathLiteral) else { return nil }
        let canonical = "\(scheme)://\(rawHost.lowercased())/\(path)"
        guard canonical == value else { return nil }
        return isAmbiguousRepositoryPath(path) ? .ambiguousRepository : .supported
    }

    private static func canonicalizeURL(_ literal: String) -> GitRepositoryEvidence {
        guard var components = URLComponents(string: literal),
              let rawScheme = components.scheme?.lowercased(),
              rawScheme == "https" || rawScheme == "ssh",
              let rawHost = components.host,
              !rawHost.isEmpty else {
            return unsupportedEvidence(credentialBearing: appearsCredentialBearing(literal))
        }

        let syntax: GitRepositorySyntax = rawScheme == "https" ? .https : .ssh
        let defaultPort = rawScheme == "https" ? 443 : 22
        guard components.port == nil || components.port == defaultPort else {
            return unsupportedEvidence(credentialBearing: appearsCredentialBearing(literal))
        }

        if rawScheme == "ssh",
           components.user != "git" || components.password != nil {
            return unsupportedEvidence(credentialBearing: components.user != nil
                || components.password != nil
                || components.query != nil
                || components.fragment != nil)
        }
        let credentialBearing = components.password != nil
            || (rawScheme == "https" && components.user != nil)
            || components.query != nil
            || components.fragment != nil

        let host = rawHost.lowercased()
        let encodedPath = components.percentEncodedPath
        guard encodedPath.hasPrefix("/") else {
            return unsupportedEvidence(credentialBearing: credentialBearing)
        }
        let untrustedPath = String(encodedPath.dropFirst())
        guard isSafeHost(host),
              let path = canonicalRepositoryPath(untrustedPath) else {
            return unsupportedEvidence(credentialBearing: credentialBearing)
        }

        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.port = nil

        let transport = rawScheme == "https" ? "https" : "ssh"
        let value = "\(transport)://\(host)/\(path)"
        let identity = CanonicalRepositoryIdentity(validatedValue: value)
        let status: GitRepositoryEvidenceStatus
        if credentialBearing {
            status = .credentialBearing
        } else if isAmbiguousRepositoryPath(path) {
            status = .ambiguousRepository
        } else {
            status = .supported
        }
        return GitRepositoryEvidence(
            identity: identity,
            displayURL: value,
            syntax: syntax,
            containedCredentialMaterial: credentialBearing,
            status: status
        )
    }

    private static func canonicalizeSCP(_ literal: String) -> GitRepositoryEvidence {
        guard !literal.contains(where: { $0.isWhitespace }),
              let at = literal.firstIndex(of: "@"),
              let colon = literal[literal.index(after: at)...].firstIndex(of: ":") else {
            return unsupportedEvidence(credentialBearing: appearsCredentialBearing(literal))
        }

        let user = String(literal[..<at])
        let host = String(literal[literal.index(after: at)..<colon]).lowercased()
        let untrustedPath = String(literal[literal.index(after: colon)...])
        let sensitiveSuffix = untrustedPath.firstIndex { $0 == "?" || $0 == "#" }
        let rawPath = sensitiveSuffix.map { String(untrustedPath[..<$0]) } ?? untrustedPath
        let credentialBearing = user.lowercased() != "git" || sensitiveSuffix != nil
        guard user == "git",
              !rawPath.hasPrefix("/"),
              isSafeHost(host),
              let path = canonicalRepositoryPath(rawPath) else {
            return unsupportedEvidence(credentialBearing: credentialBearing)
        }

        let value = "ssh://\(host)/\(path)"
        let identity = CanonicalRepositoryIdentity(validatedValue: value)
        let status: GitRepositoryEvidenceStatus
        if credentialBearing {
            status = .credentialBearing
        } else if isAmbiguousRepositoryPath(path) {
            status = .ambiguousRepository
        } else {
            status = .supported
        }
        return GitRepositoryEvidence(
            identity: identity,
            displayURL: value,
            syntax: .scp,
            containedCredentialMaterial: credentialBearing,
            status: status
        )
    }

    private static func canonicalRepositoryPath(_ rawPath: String) -> String? {
        var path = rawPath
        guard !path.hasPrefix("/") else { return nil }
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") {
            path.removeLast(4)
            // Reject repeated or slash-separated transport suffixes instead
            // of emitting an identity that a second pass would reinterpret.
            guard !path.isEmpty,
                  !path.hasSuffix("/"),
                  !path.hasSuffix(".git") else {
                return nil
            }
        }

        guard !path.isEmpty,
              !path.contains("\\"),
              !containsRejectedPercentEscape(path),
              !path.contains("//") else {
            return nil
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ component in
            !component.isEmpty && component != "." && component != ".."
        }) else {
            return nil
        }
        return path
    }

    private static func isAmbiguousRepositoryPath(_ path: String) -> Bool {
        path.split(separator: "/").count < 2
    }

    private static func isSafeHost(_ host: String) -> Bool {
        guard !host.isEmpty,
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              !host.contains("..") else {
            return false
        }
        return host.allSatisfy { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
        }
    }

    private static func containsUnsafeScalar(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || scalar.value == 0x7F
        } || value.contains(where: { $0.isWhitespace })
    }

    private static func containsRejectedPercentEscape(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return rejectedPercentEscapes.contains { lowercased.contains($0) }
    }

    private static func appearsCredentialBearing(_ value: String) -> Bool {
        if value.contains("?") || value.contains("#") {
            return true
        }

        if let schemeDelimiter = value.range(of: "://") {
            let authorityStart = schemeDelimiter.upperBound
            let authorityEnd = value[authorityStart...].firstIndex {
                $0 == "/" || $0.isWhitespace
            } ?? value.endIndex
            let authority = value[authorityStart..<authorityEnd]
            guard let at = authority.lastIndex(of: "@") else { return false }
            let scheme = value[..<schemeDelimiter.lowerBound].lowercased()
            let userInfo = authority[..<at]
            return scheme != "ssh" || userInfo != "git"
        }

        guard let at = value.firstIndex(of: "@"),
              value[value.index(after: at)...].contains(":") else {
            return false
        }
        return value[..<at] != "git"
    }

    private static func unsupportedEvidence(credentialBearing: Bool) -> GitRepositoryEvidence {
        GitRepositoryEvidence(
            identity: nil,
            displayURL: GitRepositoryEvidence.redactedDisplayURL,
            syntax: nil,
            containedCredentialMaterial: credentialBearing,
            status: .unsupportedURL
        )
    }
}

public enum GitReferenceKind: String, Sendable, Codable, CaseIterable, Hashable {
    case branch
    case tag
    case commit
    case unpinned
}

public enum GitReferenceStability: String, Sendable, Codable, CaseIterable, Hashable {
    case declaredImmutable
    case mutable
    case unpinned
}

/// A bounded Git ref. Unsafe ref values are rejected rather than persisted.
public struct GitReferenceEvidence: Sendable, Codable, Hashable {
    public let kind: GitReferenceKind
    public let value: String?
    public let declaredStability: GitReferenceStability

    public static let unpinned = GitReferenceEvidence(
        validatedKind: .unpinned,
        value: nil,
        stability: .unpinned
    )

    public static func make(kind: GitReferenceKind, value: String?) -> GitReferenceEvidence? {
        if kind == .unpinned {
            return value == nil ? .unpinned : nil
        }
        guard let value,
              isSafeReference(value, kind: kind) else {
            return nil
        }
        return GitReferenceEvidence(
            validatedKind: kind,
            value: value,
            stability: stability(for: kind)
        )
    }

    public var isFullCheckoutCommit: Bool {
        guard kind == .commit, let value else { return false }
        return Self.isFullCommit(value)
    }

    private init(validatedKind: GitReferenceKind, value: String?, stability: GitReferenceStability) {
        self.kind = validatedKind
        self.value = value
        self.declaredStability = stability
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case declaredStability
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(GitReferenceKind.self, forKey: .kind)
        let value = try container.decodeIfPresent(String.self, forKey: .value)
        let stability = try container.decode(GitReferenceStability.self, forKey: .declaredStability)
        guard let validated = Self.make(kind: kind, value: value),
              validated.declaredStability == stability else {
            throw DecodingError.dataCorruptedError(
                forKey: .declaredStability,
                in: container,
                debugDescription: "Git reference value or declared stability is invalid."
            )
        }
        self = validated
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encode(declaredStability, forKey: .declaredStability)
    }

    private static func stability(for kind: GitReferenceKind) -> GitReferenceStability {
        switch kind {
        case .branch:
            .mutable
        case .tag, .commit:
            .declaredImmutable
        case .unpinned:
            .unpinned
        }
    }

    private static func isSafeReference(_ value: String, kind: GitReferenceKind) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 255,
              value.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }),
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.contains(where: { $0.isWhitespace }),
              !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.hasSuffix("."),
              !value.lowercased().hasSuffix(".lock"),
              value != "@",
              !value.contains(".."),
              !value.contains("@{"),
              !value.contains("//"),
              !value.contains(where: { "~^:?*[\\".contains($0) }) else {
            return false
        }

        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ component in
            !component.isEmpty
                && !component.hasPrefix(".")
                && !component.lowercased().hasSuffix(".lock")
        }) else {
            return false
        }

        if kind == .commit {
            return (7...64).contains(value.utf8.count) && value.allSatisfy(isASCIIHexDigit)
        }
        return true
    }

    private static func isFullCommit(_ value: String) -> Bool {
        (value.utf8.count == 40 || value.utf8.count == 64)
            && value.allSatisfy(isASCIIHexDigit)
    }

    private static func isASCIIHexDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        return (0x30...0x39).contains(scalar.value)
            || (0x41...0x46).contains(scalar.value)
            || (0x61...0x66).contains(scalar.value)
    }
}

public struct GitDeclarationEvidence: Sendable, Codable, Hashable {
    public let repository: GitRepositoryEvidence
    public let reference: GitReferenceEvidence
    public let syntaxIsSupported: Bool

    public init(
        repository: GitRepositoryEvidence,
        reference: GitReferenceEvidence,
        syntaxIsSupported: Bool = true
    ) {
        self.repository = repository
        self.reference = reference
        self.syntaxIsSupported = syntaxIsSupported
    }
}

/// Lockfile evidence deliberately keeps the external-source declaration and the
/// concrete checkout observation separate.
public struct GitLockfileEvidence: Sendable, Codable, Hashable {
    public let externalSourceRepository: GitRepositoryEvidence?
    public let externalSourceReference: GitReferenceEvidence?
    public let checkoutRepository: GitRepositoryEvidence?
    /// Branch or tag retained by CocoaPods in CHECKOUT OPTIONS, when present.
    public let checkoutDeclaredReference: GitReferenceEvidence?
    /// Concrete checked-out commit retained by CocoaPods, when present.
    public let checkoutReference: GitReferenceEvidence?
    public let hasConflictingEvidence: Bool
    public let hasMalformedEvidence: Bool

    public init(
        externalSourceRepository: GitRepositoryEvidence? = nil,
        externalSourceReference: GitReferenceEvidence? = nil,
        checkoutRepository: GitRepositoryEvidence? = nil,
        checkoutDeclaredReference: GitReferenceEvidence? = nil,
        checkoutReference: GitReferenceEvidence? = nil,
        hasConflictingEvidence: Bool = false,
        hasMalformedEvidence: Bool = false
    ) {
        self.externalSourceRepository = externalSourceRepository
        self.externalSourceReference = externalSourceReference
        self.checkoutRepository = checkoutRepository
        self.checkoutDeclaredReference = checkoutDeclaredReference
        self.checkoutReference = checkoutReference
        self.hasConflictingEvidence = hasConflictingEvidence
        self.hasMalformedEvidence = hasMalformedEvidence
    }
}

public enum GitSourceEvidenceStatus: String, Sendable, Codable, CaseIterable {
    case supportedImmutable
    case mutable
    case unpinned
    case credentialBearing
    case incomplete
    case conflicting
    case ambiguousRepository
    case unsupportedURL
    case unsupportedSyntax
}

/// Complete, deterministic provenance for one exact CocoaPods dependency name.
public struct GitSourceProvenance: Sendable, Codable, Equatable {
    public let declarations: [GitDeclarationEvidence]
    public let lockfile: GitLockfileEvidence?
    public let status: GitSourceEvidenceStatus

    public init(
        declarations: [GitDeclarationEvidence],
        lockfile: GitLockfileEvidence? = nil
    ) {
        let declarations = declarations.sorted(by: Self.declarationPrecedes)
        self.declarations = declarations
        self.lockfile = lockfile
        self.status = Self.deriveStatus(declarations: declarations, lockfile: lockfile)
    }

    /// A Git-looking declaration whose complete Ruby option syntax was not
    /// statically representable. No raw source text is retained.
    public static var unsupportedSyntax: GitSourceProvenance {
        GitSourceProvenance(declarations: [
            GitDeclarationEvidence(
                repository: GitRepositoryCanonicalizer.evidence(
                    for: GitRepositoryEvidence.redactedDisplayURL
                ),
                reference: .unpinned,
                syntaxIsSupported: false
            ),
        ])
    }

    private enum CodingKeys: String, CodingKey {
        case declarations
        case lockfile
        case status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDeclarations = try container.decode(
            [GitDeclarationEvidence].self,
            forKey: .declarations
        )
        let lockfile = try container.decodeIfPresent(GitLockfileEvidence.self, forKey: .lockfile)
        let encodedStatus = try container.decode(GitSourceEvidenceStatus.self, forKey: .status)
        let declarations = decodedDeclarations.sorted(by: Self.declarationPrecedes)
        let derivedStatus = Self.deriveStatus(declarations: declarations, lockfile: lockfile)
        guard encodedStatus == derivedStatus else {
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Encoded Git provenance status does not match its evidence."
            )
        }
        self.declarations = declarations
        self.lockfile = lockfile
        self.status = derivedStatus
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(declarations, forKey: .declarations)
        try container.encodeIfPresent(lockfile, forKey: .lockfile)
        try container.encode(status, forKey: .status)
    }

    private static func declarationPrecedes(
        _ lhs: GitDeclarationEvidence,
        _ rhs: GitDeclarationEvidence
    ) -> Bool {
        declarationSortKey(lhs).lexicographicallyPrecedes(declarationSortKey(rhs))
    }

    private static func declarationSortKey(_ declaration: GitDeclarationEvidence) -> [String] {
        [
            declaration.repository.identity?.value ?? declaration.repository.displayURL,
            declaration.repository.syntax?.rawValue ?? "",
            declaration.reference.kind.rawValue,
            declaration.reference.value ?? "",
            declaration.syntaxIsSupported ? "1" : "0",
        ]
    }

    private static func deriveStatus(
        declarations: [GitDeclarationEvidence],
        lockfile: GitLockfileEvidence?
    ) -> GitSourceEvidenceStatus {
        let repositories = declarations.map(\.repository) + [
            lockfile?.externalSourceRepository,
            lockfile?.checkoutRepository,
        ].compactMap { $0 }

        if repositories.contains(where: { $0.containedCredentialMaterial }) {
            return .credentialBearing
        }
        if declarations.contains(where: { !$0.syntaxIsSupported }) {
            return .unsupportedSyntax
        }
        if repositories.contains(where: { $0.status == .unsupportedURL }) {
            return .unsupportedURL
        }
        if lockfile?.hasConflictingEvidence == true {
            return .conflicting
        }
        if lockfile?.hasMalformedEvidence == true {
            return .incomplete
        }
        guard !declarations.isEmpty else { return .incomplete }

        let declarationIdentities = Set(declarations.compactMap(\.repository.identity))
        let declarationReferences = Set(declarations.map(\.reference))
        guard declarationIdentities.count == 1,
              declarationReferences.count == 1,
              let declaredIdentity = declarationIdentities.first,
              let declaredReference = declarationReferences.first else {
            return .conflicting
        }

        if let externalRepository = lockfile?.externalSourceRepository?.identity,
           externalRepository != declaredIdentity {
            return .conflicting
        }
        if let checkoutRepository = lockfile?.checkoutRepository?.identity,
           checkoutRepository != declaredIdentity {
            return .conflicting
        }
        if let externalReference = lockfile?.externalSourceReference,
           externalReference != declaredReference {
            return .conflicting
        }
        if let checkoutDeclaredReference = lockfile?.checkoutDeclaredReference,
           checkoutDeclaredReference != declaredReference {
            return .conflicting
        }
        if repositories.contains(where: { $0.status == .ambiguousRepository }) {
            return .ambiguousRepository
        }

        switch declaredReference.kind {
        case .branch:
            return .mutable
        case .unpinned:
            return .unpinned
        case .tag, .commit:
            break
        }

        guard let lockfile,
              lockfile.externalSourceRepository?.identity != nil,
              lockfile.checkoutRepository?.identity != nil,
              let externalReference = lockfile.externalSourceReference,
              let checkoutReference = lockfile.checkoutReference else {
            return .incomplete
        }
        guard checkoutReference.isFullCheckoutCommit else {
            return checkoutReference.kind == .commit ? .incomplete : .conflicting
        }

        switch declaredReference.kind {
        case .tag:
            guard externalReference == declaredReference else { return .conflicting }
            return .supportedImmutable
        case .commit:
            guard externalReference == declaredReference,
                  declaredReference.isFullCheckoutCommit,
                  checkoutReference == declaredReference else {
                return .conflicting
            }
            return .supportedImmutable
        case .branch, .unpinned:
            return .conflicting
        }
    }
}

/// Additive source-evidence wrapper used by dependency and plan JSON.
///
/// The explicit discriminator avoids relying on Swift enum payload encoding and
/// leaves room for future source kinds without reinterpreting Git evidence.
public enum DependencySourceProvenance: Sendable, Codable, Equatable {
    case git(GitSourceProvenance)

    private enum CodingKeys: String, CodingKey {
        case kind
        case git
    }

    private enum Kind: String, Codable {
        case git
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .git:
            self = .git(try container.decode(GitSourceProvenance.self, forKey: .git))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .git(let provenance):
            try container.encode(Kind.git, forKey: .kind)
            try container.encode(provenance, forKey: .git)
        }
    }
}
