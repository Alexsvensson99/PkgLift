import Foundation

/// A portable structural description of one synthetic Swift library. Identical package,
/// target and library-product identities are represented by one digest. Source paths and
/// identity text remain caller-owned. This is not a manifest or a package-validity claim.
public struct GeneratedPackageBlueprint: Sendable, Equatable, Codable {
    public static let supportedShapeProfile = "single-swift-library/v1"
    public let shapeProfile: String
    public let identitySHA256: String
    public let versionSHA256: String
    public let sourceRootSHA256: String
    public let consumer: GeneratedPackageInventory.Consumer
    public let sources: [SourceReference]

    public struct SourceReference: Sendable, Equatable, Codable {
        public let declarationIndex: Int
        public let pathSHA256: String
        public let contentSHA256: String
    }

    func validate() throws {
        guard shapeProfile == Self.supportedShapeProfile,
              consumer.languageProfile == GeneratedPackageInventory.Consumer.swiftOnlyProfile else {
            throw GeneratedPackageEvidenceError.unsupportedProfile
        }
        try generatedPackageRequireDigest(identitySHA256)
        try generatedPackageRequireDigest(versionSHA256)
        try generatedPackageRequireDigest(sourceRootSHA256)
        guard generatedPackageValidDeploymentVersion(consumer.minimumVersion),
              !sources.isEmpty, sources.count <= GeneratedPackageInventory.maximumSources,
              sources.map(\.declarationIndex) == Array(0..<sources.count),
              Set(sources.map(\.pathSHA256)).count == sources.count else {
            throw GeneratedPackageEvidenceError.invalidContract
        }
        for source in sources {
            try generatedPackageRequireDigest(source.pathSHA256)
            try generatedPackageRequireDigest(source.contentSHA256)
        }
    }
}

extension GeneratedPackageBlueprint {
    private enum CodingKeys: String, CodingKey {
        case shapeProfile, identitySHA256, versionSHA256, sourceRootSHA256, consumer, sources
    }

    public init(from decoder: Decoder) throws {
        do {
            try generatedPackageRequireDecodingBoundary(decoder)
            try generatedPackageCheckShape(decoder, shape: .blueprint)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                shapeProfile: try container.decode(String.self, forKey: .shapeProfile),
                identitySHA256: try container.decode(String.self, forKey: .identitySHA256),
                versionSHA256: try container.decode(String.self, forKey: .versionSHA256),
                sourceRootSHA256: try container.decode(String.self, forKey: .sourceRootSHA256),
                consumer: try container.decode(GeneratedPackageInventory.Consumer.self, forKey: .consumer),
                sources: try container.decode([SourceReference].self, forKey: .sources)
            )
            try validate()
        } catch let error as GeneratedPackageEvidenceError {
            throw error
        } catch {
            throw GeneratedPackageEvidenceError.invalidEncoding
        }
    }
}

public struct GeneratedPackageBlueprintAssessment: Sendable, Equatable, Codable {
    public enum Outcome: String, Sendable, Codable, CaseIterable {
        case blueprintCandidate, insufficientEvidence, contradictoryEvidence, ineligibleShape

        fileprivate var priority: Int {
            switch self {
            case .blueprintCandidate: 0
            case .insufficientEvidence: 1
            case .ineligibleShape: 2
            case .contradictoryEvidence: 3
            }
        }
    }

    public struct Reason: Sendable, Hashable, Codable {
        public enum Code: String, Sendable, Codable, CaseIterable {
            case missingEvidence, incompleteSources, incompleteLanguages, incompleteTopology
            case emptySources, missingConsumer, missingSourceRoot, missingTopology
            case missingInventoryGroup, incompleteInventoryGroup
            case identityMismatch, podspecDigestMismatch, snapshotDigestMismatch
            case inventoryDigestMismatch, assessmentMismatch, selectionCardinalityMismatch
            case sourceSelectionMismatch, targetReferenceMismatch, productReferenceMismatch
            case sourceRootMismatch
            case ineligibleDeclaration, ineligibleIdentity, ineligibleSource, ineligibleTopology
            case nonemptyInventoryGroup

            fileprivate var outcome: Outcome {
                switch self {
                case .missingEvidence, .incompleteSources, .incompleteLanguages,
                     .incompleteTopology, .emptySources, .missingConsumer, .missingSourceRoot,
                     .missingTopology, .missingInventoryGroup, .incompleteInventoryGroup:
                    .insufficientEvidence
                case .identityMismatch, .podspecDigestMismatch, .snapshotDigestMismatch,
                     .inventoryDigestMismatch, .assessmentMismatch, .selectionCardinalityMismatch,
                     .sourceSelectionMismatch, .targetReferenceMismatch,
                     .productReferenceMismatch, .sourceRootMismatch:
                    .contradictoryEvidence
                case .ineligibleDeclaration, .ineligibleIdentity, .ineligibleSource,
                     .ineligibleTopology, .nonemptyInventoryGroup:
                    .ineligibleShape
                }
            }

            fileprivate var indexUpperBound: Int? {
                switch self {
                case .missingInventoryGroup, .incompleteInventoryGroup, .nonemptyInventoryGroup:
                    GeneratedPackageInventory.Group.Kind.allCases.count
                case .sourceSelectionMismatch, .targetReferenceMismatch,
                     .sourceRootMismatch, .ineligibleSource:
                    GeneratedPackageInventory.maximumSources
                case .productReferenceMismatch:
                    GeneratedPackageInventory.maximumTopologyNodes
                default: nil
                }
            }
        }

        public let code: Code
        /// Stable input-array index. Group reasons use the UTF-8-sorted exhaustive kind list.
        /// No private input label is used as a result locator.
        public let index: Int?

        private enum CodingKeys: String, CodingKey { case code, index }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(code, forKey: .code)
            try container.encode(index, forKey: .index)
        }
    }

    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let providerProfile: String
    public let pathProfile: String
    public let assessment: PodspecSwiftPMAssessment
    public let podspecSHA256: String
    public let sourceSnapshotSHA256: String?
    public let inventorySHA256: String?
    public let outcome: Outcome
    public let reasons: [Reason]
    public let dischargedReasons: [PodspecSwiftPMAssessmentReason]
    public let blueprint: GeneratedPackageBlueprint?

    fileprivate init(
        assessment: PodspecSwiftPMAssessment, podspecSHA256: String,
        sourceSnapshotSHA256: String?, inventorySHA256: String?,
        reasons: [Reason], blueprint: GeneratedPackageBlueprint?
    ) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.providerProfile = GeneratedPackageEvidence.syntheticProviderProfile
        self.pathProfile = GeneratedPackageEvidence.canonicalPathProfile
        self.assessment = assessment
        self.podspecSHA256 = podspecSHA256
        self.sourceSnapshotSHA256 = sourceSnapshotSHA256
        self.inventorySHA256 = inventorySHA256
        self.reasons = Self.canonicalReasons(reasons)
        self.outcome = Self.outcome(for: self.reasons)
        self.dischargedReasons = blueprint == nil ? [] : assessment.reasons
        self.blueprint = blueprint
        try validate()
        try generatedPackageCheckEncodedBounds(self)
    }

    public func canonicalJSON() throws -> Data { try generatedPackageEncode(self) }

    public static func decodeJSON(_ data: Data) throws -> Self {
        try generatedPackageDecode(Self.self, data: data)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, providerProfile, pathProfile, assessment, podspecSHA256
        case sourceSnapshotSHA256, inventorySHA256, outcome, reasons, dischargedReasons, blueprint
    }

    public init(from decoder: Decoder) throws {
        do {
            try generatedPackageRequireDecodingBoundary(decoder)
            try generatedPackageCheckShape(decoder, shape: Self.jsonShape)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            providerProfile = try container.decode(String.self, forKey: .providerProfile)
            pathProfile = try container.decode(String.self, forKey: .pathProfile)
            assessment = try container.decode(PodspecSwiftPMAssessment.self, forKey: .assessment)
            podspecSHA256 = try container.decode(String.self, forKey: .podspecSHA256)
            sourceSnapshotSHA256 = try container.decode(String?.self, forKey: .sourceSnapshotSHA256)
            inventorySHA256 = try container.decode(String?.self, forKey: .inventorySHA256)
            outcome = try container.decode(Outcome.self, forKey: .outcome)
            reasons = try container.decode([Reason].self, forKey: .reasons)
            dischargedReasons = try container.decode(
                [PodspecSwiftPMAssessmentReason].self, forKey: .dischargedReasons
            )
            blueprint = try container.decode(GeneratedPackageBlueprint?.self, forKey: .blueprint)
            try validate()
        } catch let error as GeneratedPackageEvidenceError {
            throw error
        } catch {
            throw GeneratedPackageEvidenceError.invalidEncoding
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(providerProfile, forKey: .providerProfile)
        try container.encode(pathProfile, forKey: .pathProfile)
        try container.encode(assessment, forKey: .assessment)
        try container.encode(podspecSHA256, forKey: .podspecSHA256)
        try container.encode(sourceSnapshotSHA256, forKey: .sourceSnapshotSHA256)
        try container.encode(inventorySHA256, forKey: .inventorySHA256)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(reasons, forKey: .reasons)
        try container.encode(dischargedReasons, forKey: .dischargedReasons)
        try container.encode(blueprint, forKey: .blueprint)
    }

    private func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw GeneratedPackageEvidenceError.unsupportedSchema
        }
        guard providerProfile == GeneratedPackageEvidence.syntheticProviderProfile,
              pathProfile == GeneratedPackageEvidence.canonicalPathProfile else {
            throw GeneratedPackageEvidenceError.unsupportedProfile
        }
        try generatedPackageRequireDigest(podspecSHA256)
        if let sourceSnapshotSHA256 { try generatedPackageRequireDigest(sourceSnapshotSHA256) }
        if let inventorySHA256 { try generatedPackageRequireDigest(inventorySHA256) }
        guard (sourceSnapshotSHA256 == nil) == (inventorySHA256 == nil),
              (sourceSnapshotSHA256 == nil) == reasons.contains(where: { $0.code == .missingEvidence }),
              reasons == Self.canonicalReasons(reasons),
              outcome == Self.outcome(for: reasons),
              reasons.allSatisfy({ reason in
                  if let bound = reason.code.indexUpperBound {
                      return reason.index.map { (0..<bound).contains($0) } == true
                  }
                  return reason.index == nil
              }) else {
            throw GeneratedPackageEvidenceError.invalidContract
        }
        if outcome == .blueprintCandidate {
            guard generatedPackageEligibleAssessment(assessment),
                  sourceSnapshotSHA256 != nil, inventorySHA256 != nil,
                  dischargedReasons == assessment.reasons, let blueprint else {
                throw GeneratedPackageEvidenceError.invalidContract
            }
            try blueprint.validate()
        } else {
            guard blueprint == nil, dischargedReasons.isEmpty else {
                throw GeneratedPackageEvidenceError.invalidContract
            }
        }
        if !generatedPackageEligibleAssessment(assessment),
           !reasons.contains(where: { $0.code == .ineligibleDeclaration }) {
            throw GeneratedPackageEvidenceError.invalidContract
        }
    }

    private static func outcome(for reasons: [Reason]) -> Outcome {
        reasons.map { $0.code.outcome }.max { $0.priority < $1.priority } ?? .blueprintCandidate
    }

    private static func canonicalReasons(_ reasons: [Reason]) -> [Reason] {
        Set(reasons).sorted { lhs, rhs in
            if lhs.code.outcome.priority != rhs.code.outcome.priority {
                return lhs.code.outcome.priority > rhs.code.outcome.priority
            }
            if lhs.code != rhs.code { return lhs.code.rawValue < rhs.code.rawValue }
            return (lhs.index ?? -1) < (rhs.index ?? -1)
        }
    }
}

/// Pure, bounded, in-memory S1 assessment. It inspects the supplied JSON bytes itself;
/// a caller cannot attach a handcrafted inspection to a different Podspec digest.
public struct GeneratedPackageBlueprintAssessor: Sendable {
    public init() {}

    public func assess(
        podspecJSON: Data, evidence: GeneratedPackageEvidence?
    ) throws -> GeneratedPackageBlueprintAssessment {
        let inspection: PodspecInspection
        let assessment: PodspecSwiftPMAssessment
        do {
            inspection = try PodspecJSONInspector().inspect(json: podspecJSON)
            assessment = try PodspecSwiftPMAssessor().assess(
                inspection, cocoaPodsProfile: .cocoaPodsCore1_17_0,
                swiftPMProfile: .swiftToolsVersion6_0
            )
        } catch {
            throw GeneratedPackageEvidenceError.invalidPodspec
        }
        let root = inspection.podspec.root
        let declarations = root.declarations.sourceFiles
        guard declarations.count <= GeneratedPackageInventory.maximumSources else {
            throw GeneratedPackageEvidenceError.limitExceeded
        }
        for path in declarations { try generatedPackageRequirePath(path) }
        guard Set(declarations.map { $0.lowercased() }).count == declarations.count else {
            throw GeneratedPackageEvidenceError.noncanonicalInventory
        }
        var reasons: [GeneratedPackageBlueprintAssessment.Reason] = []
        func add(_ code: GeneratedPackageBlueprintAssessment.Reason.Code, index: Int? = nil) {
            reasons.append(.init(code: code, index: index))
        }
        if !generatedPackageEligibleAssessment(assessment)
            || root.defaultSubspecs != .implicitAll || !root.subspecs.isEmpty
            || !root.platformScopes.isEmpty || !root.platforms.isEmpty
            || !inspection.unsupportedFields.isEmpty
            || root.declarations != PodspecScopedDeclarations(sourceFiles: declarations) {
            add(.ineligibleDeclaration)
        }
        if !generatedPackageValidIdentity(root.name) { add(.ineligibleIdentity) }
        let podspecDigest = generatedPackageSHA256(podspecJSON)
        guard let evidence else {
            add(.missingEvidence)
            return try .init(
                assessment: assessment, podspecSHA256: podspecDigest,
                sourceSnapshotSHA256: nil, inventorySHA256: nil,
                reasons: reasons, blueprint: nil
            )
        }
        try evidence.validate()
        let inventory = evidence.inventory
        let inventoryDigest = try inventory.canonicalSHA256()
        let snapshotDigest = generatedPackageSHA256(Data(evidence.snapshot.sourceSnapshotID.utf8))
        if !evidence.snapshot.name.utf8.elementsEqual(root.name.utf8)
            || !evidence.snapshot.version.utf8.elementsEqual(inspection.podspec.version.utf8) {
            add(.identityMismatch)
        }
        if evidence.snapshot.podspecSHA256 != podspecDigest { add(.podspecDigestMismatch) }
        if evidence.snapshot.sourceSnapshotSHA256 != snapshotDigest { add(.snapshotDigestMismatch) }
        if evidence.snapshot.inventorySHA256 != inventoryDigest { add(.inventoryDigestMismatch) }
        if evidence.assessment != assessment { add(.assessmentMismatch) }
        if !inventory.sourcesComplete { add(.incompleteSources) }
        if !inventory.languagesComplete { add(.incompleteLanguages) }
        if !inventory.topologyComplete { add(.incompleteTopology) }
        if inventory.sources.isEmpty { add(.emptySources) }
        if inventory.consumer == nil { add(.missingConsumer) }
        if inventory.sourceRoot == nil { add(.missingSourceRoot) }
        if inventory.sources.count != declarations.count { add(.selectionCardinalityMismatch) }

        if inventory.targets.isEmpty || inventory.products.isEmpty { add(.missingTopology) }
        if inventory.targets.count > 1 || inventory.products.count > 1
            || inventory.targets.contains(where: { $0.kind != .regular })
            || inventory.products.contains(where: { $0.kind != .library }) {
            add(.ineligibleTopology)
        }
        if inventory.targets.contains(where: { $0.name != root.name })
            || inventory.products.contains(where: { $0.name != root.name }) {
            add(.identityMismatch)
        }
        let targetNames = Set(inventory.targets.map(\.name))
        for (index, product) in inventory.products.enumerated() {
            if product.targets != [root.name] || !Set(product.targets).isSubset(of: targetNames) {
                add(.productReferenceMismatch, index: index)
            }
        }
        for (index, source) in inventory.sources.enumerated() {
            if !declarations.indices.contains(source.declarationIndex)
                || declarations[source.declarationIndex] != source.path {
                add(.sourceSelectionMismatch, index: index)
            }
            if source.language != .swift || source.kind != .regular || !source.path.hasSuffix(".swift") {
                add(.ineligibleSource, index: index)
            }
            if source.target != root.name || !targetNames.contains(source.target) {
                add(.targetReferenceMismatch, index: index)
            }
            if let sourceRoot = inventory.sourceRoot, !source.path.hasPrefix(sourceRoot + "/") {
                add(.sourceRootMismatch, index: index)
            }
        }
        let groupKinds = GeneratedPackageInventory.Group.Kind.allCases.sorted { $0.rawValue < $1.rawValue }
        for (index, kind) in groupKinds.enumerated() {
            guard let group = inventory.groups.first(where: { $0.kind == kind }) else {
                add(.missingInventoryGroup, index: index)
                continue
            }
            if !group.complete { add(.incompleteInventoryGroup, index: index) }
            if !group.entries.isEmpty { add(.nonemptyInventoryGroup, index: index) }
        }
        let blueprint: GeneratedPackageBlueprint?
        if reasons.isEmpty, let consumer = inventory.consumer, let sourceRoot = inventory.sourceRoot {
            blueprint = .init(
                shapeProfile: GeneratedPackageBlueprint.supportedShapeProfile,
                identitySHA256: generatedPackageSHA256(Data(root.name.utf8)),
                versionSHA256: generatedPackageSHA256(Data(inspection.podspec.version.utf8)),
                sourceRootSHA256: generatedPackageSHA256(Data(sourceRoot.utf8)), consumer: consumer,
                sources: inventory.sources.sorted { $0.declarationIndex < $1.declarationIndex }.map {
                    .init(declarationIndex: $0.declarationIndex,
                          pathSHA256: generatedPackageSHA256(Data($0.path.utf8)),
                          contentSHA256: $0.contentSHA256)
                }
            )
        } else {
            blueprint = nil
        }
        return try .init(
            assessment: assessment, podspecSHA256: podspecDigest,
            sourceSnapshotSHA256: snapshotDigest, inventorySHA256: inventoryDigest,
            reasons: reasons, blueprint: blueprint
        )
    }
}

private func generatedPackageEligibleAssessment(_ assessment: PodspecSwiftPMAssessment) -> Bool {
    assessment.schemaVersion == 1
        && assessment.cocoaPodsProfile == .cocoaPodsCore1_17_0
        && assessment.swiftPMProfile == .swiftToolsVersion6_0
        && assessment.outcome == .requiresGeneratedMetadata
        && assessment.reasons == [
            .init(code: .sourceSelectionRequiresGeneratedMetadata, evidencePath: "/source_files"),
        ]
}

private func generatedPackageValidIdentity(_ name: String) -> Bool {
    // An intentionally smaller synthetic profile, not the complete SwiftPM identifier grammar.
    generatedPackageMatches(name, "^[A-Z][A-Za-z0-9_]{0,63}$")
}

extension GeneratedPackageBlueprintAssessment {
    static let jsonShape: GeneratedPackageJSONShape = .object([
        "schemaVersion": .value, "providerProfile": .value, "pathProfile": .value,
        "assessment": .assessment, "podspecSHA256": .value,
        "sourceSnapshotSHA256": .nullable(.value), "inventorySHA256": .nullable(.value),
        "outcome": .value,
        "reasons": .array(.fields(["code", "index"])),
        "dischargedReasons": .array(.fields(["code", "evidencePath"])),
        "blueprint": .nullable(.blueprint),
    ])
}
