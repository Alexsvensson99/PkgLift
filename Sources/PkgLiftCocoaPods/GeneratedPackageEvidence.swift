import CryptoKit
import Foundation

/// Private caller-owned evidence. This value may contain paths and labels; only the
/// assessor's separate result is intended for portable output. No initializer does I/O.
public struct GeneratedPackageEvidence: Sendable, Equatable, Decodable {
    public static let currentSchemaVersion = 1
    public static let syntheticProviderProfile = "pkglift.synthetic-local/v1"
    public static let canonicalPathProfile = "ascii-relative-path/v1"

    public let schemaVersion: Int
    public let providerProfile: String
    public let pathProfile: String
    public let snapshot: GeneratedPackageSnapshot
    public let assessment: PodspecSwiftPMAssessment
    public let inventory: GeneratedPackageInventory

    public init(
        schemaVersion: Int,
        providerProfile: String,
        pathProfile: String,
        snapshot: GeneratedPackageSnapshot,
        assessment: PodspecSwiftPMAssessment,
        inventory: GeneratedPackageInventory
    ) throws {
        self.schemaVersion = schemaVersion
        self.providerProfile = providerProfile
        self.pathProfile = pathProfile
        self.snapshot = snapshot
        self.assessment = assessment
        self.inventory = inventory
        try validate()
    }

    /// Use this bounded boundary for untrusted JSON bytes, including duplicate-key checks.
    public static func decodeJSON(_ data: Data) throws -> Self {
        try generatedPackageDecode(Self.self, data: data)
    }

    public init(from decoder: Decoder) throws {
        do {
            try generatedPackageRequireDecodingBoundary(decoder)
            try generatedPackageCheckShape(decoder, shape: Self.jsonShape)
            let stored = try Stored(from: decoder)
            try self.init(
                schemaVersion: stored.schemaVersion,
                providerProfile: stored.providerProfile,
                pathProfile: stored.pathProfile,
                snapshot: stored.snapshot,
                assessment: stored.assessment,
                inventory: stored.inventory
            )
        } catch let error as GeneratedPackageEvidenceError {
            throw error
        } catch {
            throw GeneratedPackageEvidenceError.invalidEncoding
        }
    }

    private struct Stored: Decodable {
        let schemaVersion: Int
        let providerProfile: String
        let pathProfile: String
        let snapshot: GeneratedPackageSnapshot
        let assessment: PodspecSwiftPMAssessment
        let inventory: GeneratedPackageInventory
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw GeneratedPackageEvidenceError.unsupportedSchema
        }
        guard providerProfile == Self.syntheticProviderProfile,
              pathProfile == Self.canonicalPathProfile else {
            throw GeneratedPackageEvidenceError.unsupportedProfile
        }
        try generatedPackageRequireDigest(snapshot.podspecSHA256)
        try generatedPackageRequireDigest(snapshot.sourceSnapshotSHA256)
        try generatedPackageRequireDigest(snapshot.inventorySHA256)
        guard generatedPackageMatches(snapshot.sourceSnapshotID, "^[a-z0-9][a-z0-9._-]{0,127}$"),
              generatedPackageBoundedLabel(snapshot.name),
              generatedPackageBoundedLabel(snapshot.version) else {
            throw GeneratedPackageEvidenceError.invalidContract
        }
        try inventory.validate()
    }
}

public struct GeneratedPackageSnapshot: Sendable, Equatable, Decodable {
    public let name: String
    public let version: String
    public let podspecSHA256: String
    public let sourceSnapshotID: String
    public let sourceSnapshotSHA256: String
    public let inventorySHA256: String

    public init(
        name: String, version: String, podspecSHA256: String,
        sourceSnapshotID: String, sourceSnapshotSHA256: String, inventorySHA256: String
    ) {
        self.name = name
        self.version = version
        self.podspecSHA256 = podspecSHA256
        self.sourceSnapshotID = sourceSnapshotID
        self.sourceSnapshotSHA256 = sourceSnapshotSHA256
        self.inventorySHA256 = inventorySHA256
    }
}

/// All fields are explicit, including completeness of empty inventories. A null consumer
/// or source root represents missing evidence; decoding never invents a default.
public struct GeneratedPackageInventory: Sendable, Equatable, Codable {
    public static let maximumSources = 256
    public static let maximumTopologyNodes = 16
    public static let maximumGroupEntries = 256
    public let sourcesComplete: Bool
    public let languagesComplete: Bool
    public let topologyComplete: Bool
    public let sourceRoot: String?
    public let consumer: Consumer?
    public let sources: [Source]
    public let targets: [Target]
    public let products: [Product]
    public let groups: [Group]

    public init(
        sourcesComplete: Bool, languagesComplete: Bool, topologyComplete: Bool,
        sourceRoot: String?, consumer: Consumer?, sources: [Source],
        targets: [Target], products: [Product], groups: [Group]
    ) {
        self.sourcesComplete = sourcesComplete
        self.languagesComplete = languagesComplete
        self.topologyComplete = topologyComplete
        self.sourceRoot = sourceRoot
        self.consumer = consumer
        self.sources = sources
        self.targets = targets
        self.products = products
        self.groups = groups
    }

    /// Hashes the canonical encoding of this entire inventory, including completeness,
    /// consumer context, topology and every group. It does not hash files on disk.
    public func canonicalSHA256() throws -> String {
        try validate()
        let data = try generatedPackageEncode(self)
        guard data.count <= PodspecInspectionLimits.default.maximumJSONBytes else {
            throw GeneratedPackageEvidenceError.limitExceeded
        }
        return generatedPackageSHA256(data)
    }

    private enum CodingKeys: String, CodingKey {
        case sourcesComplete, languagesComplete, topologyComplete, sourceRoot, consumer
        case sources, targets, products, groups
    }

    public init(from decoder: Decoder) throws {
        do {
            try generatedPackageRequireDecodingBoundary(decoder)
            try generatedPackageCheckShape(decoder, shape: .inventory)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sourcesComplete = try container.decode(Bool.self, forKey: .sourcesComplete)
            languagesComplete = try container.decode(Bool.self, forKey: .languagesComplete)
            topologyComplete = try container.decode(Bool.self, forKey: .topologyComplete)
            sourceRoot = try container.decode(String?.self, forKey: .sourceRoot)
            consumer = try container.decode(Consumer?.self, forKey: .consumer)
            sources = try container.decode([Source].self, forKey: .sources)
            targets = try container.decode([Target].self, forKey: .targets)
            products = try container.decode([Product].self, forKey: .products)
            groups = try container.decode([Group].self, forKey: .groups)
            try validate()
        } catch let error as GeneratedPackageEvidenceError {
            throw error
        } catch {
            throw GeneratedPackageEvidenceError.invalidEncoding
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourcesComplete, forKey: .sourcesComplete)
        try container.encode(languagesComplete, forKey: .languagesComplete)
        try container.encode(topologyComplete, forKey: .topologyComplete)
        try container.encode(sourceRoot, forKey: .sourceRoot)
        try container.encode(consumer, forKey: .consumer)
        try container.encode(sources, forKey: .sources)
        try container.encode(targets, forKey: .targets)
        try container.encode(products, forKey: .products)
        try container.encode(groups, forKey: .groups)
    }

    public struct Source: Sendable, Equatable, Codable {
        public enum Language: String, Sendable, Codable, CaseIterable {
            case swift, objectiveC, objectiveCPlusPlus, c, cPlusPlus, mixed, unknown
        }
        public enum Kind: String, Sendable, Codable, CaseIterable {
            case regular, generated, symbolicLink, unknown
        }
        public let declarationIndex: Int
        public let path: String
        public let contentSHA256: String
        public let language: Language
        public let kind: Kind
        public let target: String

        public init(
            declarationIndex: Int, path: String, contentSHA256: String,
            language: Language, kind: Kind, target: String
        ) {
            self.declarationIndex = declarationIndex
            self.path = path
            self.contentSHA256 = contentSHA256
            self.language = language
            self.kind = kind
            self.target = target
        }
    }

    public struct Consumer: Sendable, Equatable, Codable {
        public static let swiftOnlyProfile = "swift-only/v1"
        public let platform: PodspecPlatform
        public let minimumVersion: String
        public let languageProfile: String

        public init(platform: PodspecPlatform, minimumVersion: String, languageProfile: String) {
            self.platform = platform
            self.minimumVersion = minimumVersion
            self.languageProfile = languageProfile
        }
    }

    public struct Target: Sendable, Equatable, Codable {
        public enum Kind: String, Sendable, Codable, CaseIterable {
            case regular, test, executable, macro, plugin, binary, systemLibrary
        }
        public let name: String
        public let kind: Kind
        public init(name: String, kind: Kind) {
            self.name = name
            self.kind = kind
        }
    }

    public struct Product: Sendable, Equatable, Codable {
        public enum Kind: String, Sendable, Codable, CaseIterable {
            case library, executable, plugin
        }
        public let name: String
        public let kind: Kind
        public let targets: [String]
        public init(name: String, kind: Kind, targets: [String]) {
            self.name = name
            self.kind = kind
            self.targets = targets
        }
    }

    public struct Group: Sendable, Equatable, Codable {
        public enum Kind: String, Sendable, Codable, CaseIterable {
            case cocoaPodsDependencies, dependencyProducts, resources, resourceBundles
            case publicHeaders, privateHeaders, projectHeaders
            case frameworks, weakFrameworks, libraries, vendoredArtifacts
            case moduleMaps, moduleLayouts, compilerFlags, buildSettings
            case configurationDependencies, arcControls, excludedFiles, preservedPaths
            case generatedFiles, scripts, hooks, deferredDeclarations
        }
        public let kind: Kind
        public let complete: Bool
        public let entries: [String]
        public init(kind: Kind, complete: Bool, entries: [String]) {
            self.kind = kind
            self.complete = complete
            self.entries = entries
        }
    }

    func validate() throws {
        guard sources.count <= Self.maximumSources, targets.count <= Self.maximumTopologyNodes,
              products.count <= Self.maximumTopologyNodes, groups.count <= Group.Kind.allCases.count,
              products.allSatisfy({ $0.targets.count <= Self.maximumTopologyNodes }),
              groups.allSatisfy({ $0.entries.count <= Self.maximumGroupEntries }) else {
            throw GeneratedPackageEvidenceError.limitExceeded
        }
        if let sourceRoot { try generatedPackageRequirePath(sourceRoot) }
        if let consumer {
            guard consumer.languageProfile == Consumer.swiftOnlyProfile else {
                throw GeneratedPackageEvidenceError.unsupportedProfile
            }
            guard generatedPackageValidDeploymentVersion(consumer.minimumVersion) else {
                throw GeneratedPackageEvidenceError.invalidContract
            }
        }
        let indices = sources.map(\.declarationIndex)
        guard Set(indices).count == indices.count,
              indices.allSatisfy({ (0..<Self.maximumSources).contains($0) }) else {
            throw GeneratedPackageEvidenceError.noncanonicalInventory
        }
        for source in sources {
            try generatedPackageRequirePath(source.path)
            try generatedPackageRequireDigest(source.contentSHA256)
            guard generatedPackageBoundedLabel(source.target) else {
                throw GeneratedPackageEvidenceError.invalidContract
            }
        }
        try generatedPackageRequireCanonical(sources.map(\.path), caseInsensitive: true)
        try generatedPackageRequireCanonical(targets.map(\.name), caseInsensitive: true)
        try generatedPackageRequireCanonical(products.map(\.name), caseInsensitive: true)
        for product in products {
            try generatedPackageRequireCanonical(product.targets, caseInsensitive: true)
        }
        try generatedPackageRequireCanonical(groups.map { $0.kind.rawValue })
        for group in groups { try generatedPackageRequireCanonical(group.entries) }
    }
}

/// Deliberately excludes caller values, decoder paths, and nested error descriptions.
public enum GeneratedPackageEvidenceError: Swift.Error, LocalizedError, Sendable, Equatable {
    case unsupportedSchema, unsupportedProfile, invalidDigest, invalidPath
    case noncanonicalInventory, invalidContract, invalidEncoding, invalidPodspec, limitExceeded

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "Unsupported generated-package evidence schema."
        case .unsupportedProfile: "Unsupported generated-package evidence profile."
        case .invalidDigest: "Evidence digests must be lowercase SHA-256 values."
        case .invalidPath: "Evidence paths must use the pinned relative path profile."
        case .noncanonicalInventory: "Evidence inventories must be ordered and unique."
        case .invalidContract: "Generated-package evidence violates its value contract."
        case .invalidEncoding: "Generated-package JSON violates its decoding contract."
        case .invalidPodspec: "Podspec JSON cannot be inspected under the pinned profile."
        case .limitExceeded: "Generated-package evidence exceeds the bounded profile."
        }
    }
}

func generatedPackageSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func generatedPackageMatches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) == value.startIndex..<value.endIndex
}

func generatedPackageRequireDigest(_ value: String) throws {
    guard generatedPackageMatches(value, "^[0-9a-f]{64}$") else {
        throw GeneratedPackageEvidenceError.invalidDigest
    }
}

func generatedPackageRequirePath(_ path: String) throws {
    guard path.utf8.count <= 512,
          generatedPackageMatches(path, "^[A-Za-z0-9_./-]+$"),
          path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
              !$0.isEmpty && $0 != "." && $0 != ".."
          }) else {
        throw GeneratedPackageEvidenceError.invalidPath
    }
}

func generatedPackageBoundedLabel(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 512
        && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
}

func generatedPackageRequireCanonical(_ values: [String], caseInsensitive: Bool = false) throws {
    guard values.count <= 4_096, values.allSatisfy(generatedPackageBoundedLabel) else {
        throw GeneratedPackageEvidenceError.invalidContract
    }
    let keys = caseInsensitive ? values.map { $0.lowercased() } : values
    guard Set(keys).count == keys.count,
          values == values.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) else {
        throw GeneratedPackageEvidenceError.noncanonicalInventory
    }
}

func generatedPackageValidDeploymentVersion(_ value: String) -> Bool {
    // major.minor, or major.minor.patch with a nonzero patch; no alternate spelling.
    generatedPackageMatches(value, "^[1-9][0-9]{0,2}\\.(0|[1-9][0-9]{0,2})(\\.[1-9][0-9]{0,2})?$")
}
