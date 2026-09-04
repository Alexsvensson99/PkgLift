import CryptoKit
import Foundation
import Testing
@testable import PkgLiftCocoaPods

@Suite("Generated Package S1 Blueprint Tests")
struct GeneratedPackageBlueprintTests {
    typealias Inventory = GeneratedPackageInventory
    typealias Evidence = GeneratedPackageEvidence
    typealias Result = GeneratedPackageBlueprintAssessment

    @Test("The repository-owned S1 fixture is a deterministic candidate retaining v0.5")
    func s1FixtureCandidateAndRoundTrip() throws {
        let podspec = try fixtureData("S1Sample-1.0.0.podspec", fileExtension: "json")
        let evidence = try fixtureEvidence()
        let assessor = GeneratedPackageBlueprintAssessor()
        let directV05 = try assessor.assess(podspecJSON: podspec, evidence: nil).assessment
        let result = try assessor.assess(podspecJSON: podspec, evidence: evidence)

        #expect(sha256(podspec) == evidence.snapshot.podspecSHA256)
        #expect(try evidence.inventory.canonicalSHA256() == evidence.snapshot.inventorySHA256)
        #expect(result.outcome == .blueprintCandidate)
        #expect(result.assessment == directV05)
        #expect(result.assessment == evidence.assessment)
        #expect(result.dischargedReasons == directV05.reasons)
        #expect(result.blueprint?.sources.count == 2)
        #expect(result.sourceSnapshotSHA256 == evidence.snapshot.sourceSnapshotSHA256)

        let first = try result.canonicalJSON()
        let second = try assessor.assess(podspecJSON: podspec, evidence: evidence).canonicalJSON()
        #expect(first == second)
        #expect(try Result.decodeJSON(first) == result)
    }

    @Test("The fixture documents asserted content separately from measured bytes")
    func fixtureByteDigests() throws {
        let podspec = try fixtureData("S1Sample-1.0.0.podspec", fileExtension: "json")
        let alpha = try fixtureData("Alpha", fileExtension: "swift", subdirectory: "Sources")
        let beta = try fixtureData("Beta", fileExtension: "swift", subdirectory: "Sources")
        let evidence = try fixtureEvidence()

        #expect(sha256(podspec) == "a696bb0855dab24029586a2c9c985e97cc68a172e349c778a88543f841159583")
        #expect(sha256(alpha) == "96b3c9ff869a77fc84acc3377f049d1a31169718262591cebf5e3dfc34dbadd7")
        #expect(sha256(beta) == "9a31b54ad4aded4f93128d6fcf33fa6798f6c84992e20ba14837eb039ef7e810")
        #expect(evidence.inventory.sources.map(\.contentSHA256) == [sha256(alpha), sha256(beta)])
    }

    @Test("S1 classifies all four result outcomes")
    func resultOutcomes() throws {
        let podspec = try fixturePodspec()
        let assessor = GeneratedPackageBlueprintAssessor()
        let baseline = try fixtureEvidence()

        #expect(try assessor.assess(podspecJSON: podspec, evidence: nil).outcome == .insufficientEvidence)

        let contradictory = try Evidence(
            schemaVersion: Evidence.currentSchemaVersion,
            providerProfile: Evidence.syntheticProviderProfile,
            pathProfile: Evidence.canonicalPathProfile,
            snapshot: GeneratedPackageSnapshot(
                name: "Different", version: baseline.snapshot.version,
                podspecSHA256: baseline.snapshot.podspecSHA256,
                sourceSnapshotID: baseline.snapshot.sourceSnapshotID,
                sourceSnapshotSHA256: baseline.snapshot.sourceSnapshotSHA256,
                inventorySHA256: baseline.snapshot.inventorySHA256
            ),
            assessment: baseline.assessment,
            inventory: baseline.inventory
        )
        #expect(try assessor.assess(podspecJSON: podspec, evidence: contradictory).outcome == .contradictoryEvidence)

        let ineligiblePodspec = Data(#"{"name":"S1Sample","version":"1.0.0","source_files":["Sources/Alpha.swift","Sources/Beta.swift"],"resources":["Resources/a"]}"#.utf8)
        let ineligibleAssessment = try assessor.assess(
            podspecJSON: ineligiblePodspec, evidence: nil
        ).assessment
        let ineligibleEvidence = try freshEvidence(
            inventory: baseline.inventory,
            assessment: ineligibleAssessment,
            podspec: ineligiblePodspec
        )
        #expect(try assessor.assess(
            podspecJSON: ineligiblePodspec, evidence: ineligibleEvidence
        ).outcome == .ineligibleShape)
        #expect(try assessor.assess(podspecJSON: podspec, evidence: baseline).outcome == .blueprintCandidate)
    }

    @Test("Every S1 reason code is reachable through bounded supplied evidence")
    func everyReasonCode() throws {
        let podspec = try fixturePodspec()
        let assessor = GeneratedPackageBlueprintAssessor()
        let base = try fixtureEvidence()
        var observed: Set<Result.Reason.Code> = []

        func collect(_ evidence: Evidence?, podspec: Data) throws {
            let result = try assessor.assess(podspecJSON: podspec, evidence: evidence)
            observed.formUnion(result.reasons.map(\.code))
        }

        try collect(nil, podspec: podspec)
        try collect(try freshEvidence(inventory: copiedInventory(
            base.inventory, sourcesComplete: false, languagesComplete: false, topologyComplete: false,
            sources: [], removeConsumer: true, removeSourceRoot: true, targets: [], products: [], groups: []
        )), podspec: podspec)

        let kinds = orderedGroupKinds()
        for kind in kinds {
            guard let index = kinds.firstIndex(of: kind) else { throw FixtureError.invalidFixture }
            let incomplete = copiedInventory(base.inventory, groups: base.inventory.groups.map { group in
                group.kind == kind ? .init(kind: group.kind, complete: false, entries: group.entries) : group
            })
            let nonempty = copiedInventory(base.inventory, groups: base.inventory.groups.map { group in
                group.kind == kind ? .init(kind: group.kind, complete: group.complete, entries: ["entry"]) : group
            })
            let missing = copiedInventory(base.inventory, groups: base.inventory.groups.filter { $0.kind != kind })
            for inventory in [incomplete, nonempty, missing] {
                let result = try assessor.assess(
                    podspecJSON: podspec, evidence: freshEvidence(inventory: inventory)
                )
                observed.formUnion(result.reasons.map(\.code))
                let expected: Result.Reason.Code = inventory.groups.contains(where: { $0.kind == kind })
                    ? (inventory.groups.first(where: { $0.kind == kind })?.complete == false
                        ? .incompleteInventoryGroup : .nonemptyInventoryGroup)
                    : .missingInventoryGroup
                #expect(result.reasons.contains(.init(code: expected, index: index)))
            }
        }

        let oneSource = [base.inventory.sources[0]]
        try collect(try freshEvidence(inventory: copiedInventory(base.inventory, sources: oneSource)), podspec: podspec)
        let wrongSelection = [
            Inventory.Source(declarationIndex: 1, path: base.inventory.sources[0].path,
                             contentSHA256: base.inventory.sources[0].contentSHA256,
                             language: .swift, kind: .regular, target: "S1Sample"),
            Inventory.Source(declarationIndex: 0, path: base.inventory.sources[1].path,
                             contentSHA256: base.inventory.sources[1].contentSHA256,
                             language: .swift, kind: .regular, target: "S1Sample"),
        ]
        try collect(try freshEvidence(inventory: copiedInventory(base.inventory, sources: wrongSelection)), podspec: podspec)
        let wrongTarget = base.inventory.sources.enumerated().map { index, source in
            Inventory.Source(declarationIndex: source.declarationIndex, path: source.path,
                             contentSHA256: source.contentSHA256, language: source.language,
                             kind: source.kind, target: index == 0 ? "Elsewhere" : source.target)
        }
        try collect(try freshEvidence(inventory: copiedInventory(base.inventory, sources: wrongTarget)), podspec: podspec)
        let wrongProduct = [Inventory.Product(name: "S1Sample", kind: .library, targets: ["Elsewhere"])]
        try collect(try freshEvidence(inventory: copiedInventory(base.inventory, products: wrongProduct)), podspec: podspec)
        try collect(try freshEvidence(inventory: copiedInventory(base.inventory, sourceRoot: "Elsewhere")), podspec: podspec)

        let nonSwift = base.inventory.sources.enumerated().map { index, source in
            Inventory.Source(declarationIndex: source.declarationIndex, path: source.path,
                             contentSHA256: source.contentSHA256,
                             language: index == 0 ? .objectiveC : source.language,
                             kind: source.kind, target: source.target)
        }
        try collect(try freshEvidence(inventory: copiedInventory(base.inventory, sources: nonSwift)), podspec: podspec)
        let extraTarget = [Inventory.Target(name: "Elsewhere", kind: .regular),
                           Inventory.Target(name: "S1Sample", kind: .regular)]
        try collect(try freshEvidence(inventory: copiedInventory(base.inventory, targets: extraTarget)), podspec: podspec)

        let metadataOnly = Data(#"{"name":"S1Sample","version":"1.0.0","source_files":["Sources/Alpha.swift","Sources/Beta.swift"],"resources":["Resources/a"]}"#.utf8)
        let metadataAssessment = try assessor.assess(podspecJSON: metadataOnly, evidence: nil).assessment
        try collect(try freshEvidence(inventory: base.inventory, assessment: metadataAssessment, podspec: metadataOnly), podspec: metadataOnly)
        let invalidIdentity = Data(#"{"name":"lowercase","version":"1.0.0","source_files":["Sources/Alpha.swift","Sources/Beta.swift"]}"#.utf8)
        let identityAssessment = try assessor.assess(podspecJSON: invalidIdentity, evidence: nil).assessment
        try collect(try freshEvidence(inventory: base.inventory, assessment: identityAssessment,
                                      podspec: invalidIdentity, name: "lowercase"), podspec: invalidIdentity)

        let alteredAssessment = try assessor.assess(
            podspecJSON: Data(#"{"name":"S1Sample","version":"1.0.0","source_files":["Sources/Alpha.swift"],"module_name":"A"}"#.utf8),
            evidence: nil
        ).assessment
        try collect(try freshEvidence(inventory: base.inventory, assessment: alteredAssessment), podspec: podspec)
        for evidence in [
            try freshEvidence(inventory: base.inventory, podspecDigest: digest("different-podspec")),
            try freshEvidence(inventory: base.inventory, sourceSnapshotDigest: digest("different-snapshot")),
            try freshEvidence(inventory: base.inventory, inventoryDigest: digest("different-inventory")),
        ] {
            try collect(evidence, podspec: podspec)
        }

        #expect(observed == Set(Result.Reason.Code.allCases))
    }

    @Test("Raw paths and canonical inventory order are validated before assessment")
    func inventoryContractFailures() throws {
        let base = try fixtureEvidence().inventory
        let invalidPath = copiedInventory(base, sources: [
            Inventory.Source(declarationIndex: 0, path: "/absolute.swift", contentSHA256: base.sources[0].contentSHA256, language: .swift, kind: .regular, target: "S1Sample"),
            base.sources[1],
        ])
        let duplicate = copiedInventory(base, sources: [base.sources[0],
            Inventory.Source(declarationIndex: 1, path: base.sources[0].path, contentSHA256: base.sources[1].contentSHA256, language: .swift, kind: .regular, target: "S1Sample")])
        let caseCollision = copiedInventory(base, sources: [base.sources[0],
            Inventory.Source(declarationIndex: 1, path: "Sources/alpha.swift", contentSHA256: base.sources[1].contentSHA256, language: .swift, kind: .regular, target: "S1Sample")])
        let unsorted = copiedInventory(base, sources: [base.sources[1], base.sources[0]])

        #expect(throws: GeneratedPackageEvidenceError.invalidPath) { try freshEvidence(inventory: invalidPath) }
        #expect(throws: GeneratedPackageEvidenceError.noncanonicalInventory) { try freshEvidence(inventory: duplicate) }
        #expect(throws: GeneratedPackageEvidenceError.noncanonicalInventory) { try freshEvidence(inventory: caseCollision) }
        #expect(throws: GeneratedPackageEvidenceError.noncanonicalInventory) { try freshEvidence(inventory: unsorted) }

        for rawPath in [
            "/absolute.swift", "Sources/*.swift", "Sources\\Alpha.swift", "Sources/\u{0001}.swift",
            "Sources//Alpha.swift", "Sources/./Alpha.swift", "Sources/../Alpha.swift",
        ] {
            let invalid = copiedInventory(base, sources: [
                Inventory.Source(declarationIndex: 0, path: rawPath,
                                 contentSHA256: base.sources[0].contentSHA256,
                                 language: .swift, kind: .regular, target: "S1Sample"),
            ])
            #expect(throws: GeneratedPackageEvidenceError.invalidPath) {
                try freshEvidence(inventory: invalid)
            }
        }
    }

    @Test("Consumer requirements and every non-library target kind prevent candidacy")
    func consumerAndTargetShapeBoundaries() throws {
        let base = try fixtureEvidence().inventory
        let assessor = GeneratedPackageBlueprintAssessor()
        let podspec = try fixturePodspec()
        let unsupportedConsumer = copiedInventory(
            base,
            consumer: Inventory.Consumer(platform: .iOS, minimumVersion: "15.0", languageProfile: "mixed/v1")
        )
        let invalidMinimum = copiedInventory(
            base,
            consumer: Inventory.Consumer(platform: .iOS, minimumVersion: "0.0", languageProfile: "swift-only/v1")
        )
        #expect(throws: GeneratedPackageEvidenceError.unsupportedProfile) {
            try freshEvidence(inventory: unsupportedConsumer)
        }
        #expect(throws: GeneratedPackageEvidenceError.invalidContract) {
            try freshEvidence(inventory: invalidMinimum)
        }

        for kind in Inventory.Target.Kind.allCases where kind != .regular {
            let inventory = copiedInventory(base, targets: [Inventory.Target(name: "S1Sample", kind: kind)])
            let result = try assessor.assess(
                podspecJSON: podspec, evidence: freshEvidence(inventory: inventory)
            )
            #expect(result.outcome == .ineligibleShape)
            #expect(result.reasons.contains(.init(code: .ineligibleTopology, index: nil)))
        }
    }

    @Test("Unsupported declaration shapes retain v0.5 and cannot become candidates")
    func declarationBoundaries() throws {
        let assessor = GeneratedPackageBlueprintAssessor()
        let inventory = try fixtureEvidence().inventory
        let documents = [
            #"{"name":"S1Sample","version":"1.0.0","source_files":["Sources/Alpha.swift","Sources/Beta.swift"],"source":{"git":"https://example.invalid/private.git"}}"#,
            #"{"name":"S1Sample","version":"1.0.0","source_files":["Sources/Alpha.swift","Sources/Beta.swift"],"platforms":{"ios":"15.0"}}"#,
            #"{"name":"S1Sample","version":"1.0.0","source_files":["Sources/Alpha.swift","Sources/Beta.swift"],"dependencies":{"Other":[]}}"#,
            #"{"name":"S1Sample","version":"1.0.0","source_files":["Sources/Alpha.swift","Sources/Beta.swift"],"compiler_flags":"-DSECRET"}"#,
            #"{"name":"S1Sample","version":"1.0.0","source_files":["Sources/Alpha.swift","Sources/Beta.swift"],"subspecs":[{"name":"Child"}]}"#,
        ]
        for document in documents {
            let podspec = Data(document.utf8)
            let assessment = try assessor.assess(podspecJSON: podspec, evidence: nil).assessment
            let evidence = try freshEvidence(
                inventory: inventory, assessment: assessment, podspec: podspec
            )
            let result = try assessor.assess(podspecJSON: podspec, evidence: evidence)
            #expect(result.outcome == .ineligibleShape)
            #expect(result.assessment == assessment)
            #expect(result.reasons.contains(.init(code: .ineligibleDeclaration, index: nil)))
        }
    }

    @Test("Digest bindings are exact bytes, including semantically equivalent whitespace")
    func byteExactPodspecBinding() throws {
        let original = try fixturePodspec()
        let compact = Data(#"{"name":"S1Sample","version":"1.0.0","source_files":["Sources/Alpha.swift","Sources/Beta.swift"]}"#.utf8)
        let result = try GeneratedPackageBlueprintAssessor().assess(
            podspecJSON: compact, evidence: try fixtureEvidence()
        )
        #expect(sha256(original) != sha256(compact))
        #expect(result.reasons.contains(.init(code: .podspecDigestMismatch, index: nil)))
    }

    @Test("A literal singleton selection can be a candidate, while unsafe raw paths fail closed")
    func singletonSelectionAndRawPodspecPathBoundary() throws {
        let singleton = Data(#"{"name":"S1Sample","version":"1.0.0","source_files":"Sources/Alpha.swift"}"#.utf8)
        let base = try fixtureEvidence().inventory
        let singletonInventory = copiedInventory(base, sources: [base.sources[0]])
        let singletonAssessment = try GeneratedPackageBlueprintAssessor().assess(
            podspecJSON: singleton, evidence: nil
        ).assessment
        let singletonEvidence = try freshEvidence(
            inventory: singletonInventory, assessment: singletonAssessment, podspec: singleton
        )
        #expect(try GeneratedPackageBlueprintAssessor().assess(
            podspecJSON: singleton, evidence: singletonEvidence
        ).outcome == .blueprintCandidate)

        for rawPath in ["Sources/*.swift", "/absolute.swift", "Sources\\Alpha.swift"] {
            let podspec = try JSONSerialization.data(withJSONObject: [
                "name": "S1Sample",
                "version": "1.0.0",
                "source_files": [rawPath],
            ])
            #expect(throws: GeneratedPackageEvidenceError.invalidPath) {
                try GeneratedPackageBlueprintAssessor().assess(podspecJSON: podspec, evidence: nil)
            }
        }
    }

    @Test("A forged but syntactically valid v0.5 locator is contradictory caller evidence")
    func callerAssessmentBinding() throws {
        let podspec = try fixturePodspec()
        var object = try fixtureJSONObject()
        guard var assessment = object["assessment"] as? [String: Any] else {
            throw FixtureError.invalidFixture
        }
        assessment["reasons"] = [[
            "code": "sourceSelectionRequiresGeneratedMetadata",
            "evidencePath": "/forged",
        ]]
        object["assessment"] = assessment
        let forged = try Evidence.decodeJSON(try jsonData(object))
        let result = try GeneratedPackageBlueprintAssessor().assess(
            podspecJSON: podspec, evidence: forged
        )
        #expect(result.assessment != forged.assessment)
        #expect(result.reasons.contains(.init(code: .assessmentMismatch, index: nil)))
    }

    @Test("Evidence decoding rejects missing, unknown, duplicate, schema, and profile fields")
    func evidenceDecodingBoundary() throws {
        for field in ["inventory", "sourcesComplete", "languagesComplete", "topologyComplete"] {
            var object = try fixtureJSONObject()
            if field == "inventory" {
                object.removeValue(forKey: field)
            } else {
                guard var inventory = object["inventory"] as? [String: Any] else {
                    throw FixtureError.invalidFixture
                }
                inventory.removeValue(forKey: field)
                object["inventory"] = inventory
            }
            #expect(throws: GeneratedPackageEvidenceError.invalidEncoding) {
                try Evidence.decodeJSON(try jsonData(object))
            }
        }

        var object = try fixtureJSONObject()
        object["unexpected"] = true
        #expect(throws: GeneratedPackageEvidenceError.invalidEncoding) {
            try Evidence.decodeJSON(try jsonData(object))
        }

        object = try fixtureJSONObject()
        guard var inventory = object["inventory"] as? [String: Any],
              var groups = inventory["groups"] as? [[String: Any]],
              !groups.isEmpty else {
            throw FixtureError.invalidFixture
        }
        groups[0].removeValue(forKey: "complete")
        inventory["groups"] = groups
        object["inventory"] = inventory
        #expect(throws: GeneratedPackageEvidenceError.invalidEncoding) {
            try Evidence.decodeJSON(try jsonData(object))
        }

        object = try fixtureJSONObject()
        object["schemaVersion"] = 99
        #expect(throws: GeneratedPackageEvidenceError.unsupportedSchema) {
            try Evidence.decodeJSON(try jsonData(object))
        }

        object = try fixtureJSONObject()
        guard var snapshot = object["snapshot"] as? [String: Any] else {
            throw FixtureError.invalidFixture
        }
        snapshot["podspecSHA256"] = "not-a-digest"
        object["snapshot"] = snapshot
        #expect(throws: GeneratedPackageEvidenceError.invalidDigest) {
            try Evidence.decodeJSON(try jsonData(object))
        }

        object = try fixtureJSONObject()
        guard var uppercaseSnapshot = object["snapshot"] as? [String: Any] else {
            throw FixtureError.invalidFixture
        }
        uppercaseSnapshot["inventorySHA256"] = String(repeating: "A", count: 64)
        object["snapshot"] = uppercaseSnapshot
        #expect(throws: GeneratedPackageEvidenceError.invalidDigest) {
            try Evidence.decodeJSON(try jsonData(object))
        }

        object = try fixtureJSONObject()
        object["providerProfile"] = "unregistered/v9"
        #expect(throws: GeneratedPackageEvidenceError.unsupportedProfile) {
            try Evidence.decodeJSON(try jsonData(object))
        }

        object = try fixtureJSONObject()
        object["pathProfile"] = "unregistered-path/v9"
        #expect(throws: GeneratedPackageEvidenceError.unsupportedProfile) {
            try Evidence.decodeJSON(try jsonData(object))
        }

        object = try fixtureJSONObject()
        guard var nestedInventory = object["inventory"] as? [String: Any] else {
            throw FixtureError.invalidFixture
        }
        nestedInventory["unexpected"] = true
        object["inventory"] = nestedInventory
        #expect(throws: GeneratedPackageEvidenceError.invalidEncoding) {
            try Evidence.decodeJSON(try jsonData(object))
        }

        let canonical = String(decoding: try jsonData(try fixtureJSONObject()), as: UTF8.self)
        let duplicate = Data((String(canonical.dropLast()) + #","schemaVersion":1}"#).utf8)
        _ = try JSONSerialization.jsonObject(with: duplicate)
        #expect(throws: GeneratedPackageEvidenceError.invalidEncoding) {
            try Evidence.decodeJSON(duplicate)
        }
    }

    @Test("Result decoding validates state, reasons, discharged evidence, and blueprint")
    func resultDecodingBoundaryAndPrivacy() throws {
        let podspec = try fixturePodspec()
        let evidence = try fixtureEvidence()
        let candidate = try GeneratedPackageBlueprintAssessor().assess(
            podspecJSON: podspec, evidence: evidence
        )
        let canonical = try candidate.canonicalJSON()
        for mutation in [
            { (object: inout [String: Any]) in object["outcome"] = "insufficientEvidence" },
            { (object: inout [String: Any]) in object["reasons"] = [["code": "emptySources", "index": NSNull()]] },
            { (object: inout [String: Any]) in object["reasons"] = [["code": "missingEvidence", "index": 7]] },
            { (object: inout [String: Any]) in object["dischargedReasons"] = [] },
            { (object: inout [String: Any]) in object["blueprint"] = NSNull() },
        ] {
            var object = try JSONObject(data: canonical)
            mutation(&object)
            #expect(throws: GeneratedPackageEvidenceError.invalidContract) {
                try Result.decodeJSON(try jsonData(object))
            }
        }

        let privateSnapshot = try freshEvidence(
            inventory: copiedInventory(try fixtureEvidence().inventory, sources: [
                Inventory.Source(declarationIndex: 0, path: "Sources/A_RAW_TOKEN_987.swift", contentSHA256: digest("secret-content"), language: .swift, kind: .regular, target: "S1Sample"),
                (try fixtureEvidence()).inventory.sources[1],
            ]),
            snapshotID: "raw-snapshot-secret-987"
        )
        let privateResult = try GeneratedPackageBlueprintAssessor().assess(
            podspecJSON: podspec, evidence: privateSnapshot
        )
        let output = String(decoding: try privateResult.canonicalJSON(), as: UTF8.self)
        let errorText = GeneratedPackageEvidenceError.invalidContract.errorDescription ?? ""
        for sentinel in ["RAW_TOKEN_987", "raw-snapshot-secret-987", "secret-content"] {
            #expect(!output.contains(sentinel))
            #expect(!errorText.contains(sentinel))
        }

        let unicodePodspec = Data(#"{"name":"S1Sample","version":"1.0.é","source_files":["Sources/Alpha.swift","Sources/Beta.swift"]}"#.utf8)
        let unicodeAssessment = try GeneratedPackageBlueprintAssessor().assess(
            podspecJSON: unicodePodspec, evidence: nil
        ).assessment
        let decomposedVersionEvidence = try freshEvidence(
            inventory: evidence.inventory, assessment: unicodeAssessment, podspec: unicodePodspec,
            version: "1.0.e\u{301}"
        )
        let unicodeResult = try GeneratedPackageBlueprintAssessor().assess(
            podspecJSON: unicodePodspec, evidence: decomposedVersionEvidence
        )
        #expect(unicodeResult.reasons.contains(.init(code: .identityMismatch, index: nil)))
    }

    @Test("Negative results reject duplicate, noncanonical, and out-of-budget reason indices")
    func negativeResultReasonDecodingBoundaries() throws {
        let podspec = try fixturePodspec()
        let assessor = GeneratedPackageBlueprintAssessor()
        let insufficient = try assessor.assess(podspecJSON: podspec, evidence: nil)
        var object = try JSONObject(data: try insufficient.canonicalJSON())
        object["reasons"] = [
            ["code": "missingEvidence", "index": NSNull()],
            ["code": "missingEvidence", "index": NSNull()],
        ]
        #expect(throws: GeneratedPackageEvidenceError.invalidContract) {
            try Result.decodeJSON(try jsonData(object))
        }
        object["reasons"] = [
            ["code": "missingEvidence", "index": NSNull()],
            ["code": "incompleteSources", "index": NSNull()],
        ]
        #expect(throws: GeneratedPackageEvidenceError.invalidContract) {
            try Result.decodeJSON(try jsonData(object))
        }

        let base = try fixtureEvidence().inventory
        let sourceMismatch = copiedInventory(base, sources: [
            Inventory.Source(declarationIndex: 1, path: base.sources[0].path,
                             contentSHA256: base.sources[0].contentSHA256,
                             language: .swift, kind: .regular, target: "S1Sample"),
            Inventory.Source(declarationIndex: 0, path: base.sources[1].path,
                             contentSHA256: base.sources[1].contentSHA256,
                             language: .swift, kind: .regular, target: "S1Sample"),
        ])
        let sourceResult = try assessor.assess(
            podspecJSON: podspec, evidence: freshEvidence(inventory: sourceMismatch)
        )
        try expectIndexBoundary(sourceResult, code: .sourceSelectionMismatch, valid: 255, invalid: 256)

        let productMismatch = copiedInventory(base, products: [
            Inventory.Product(name: "S1Sample", kind: .library, targets: ["Elsewhere"]),
        ])
        let productResult = try assessor.assess(
            podspecJSON: podspec, evidence: freshEvidence(inventory: productMismatch)
        )
        try expectIndexBoundary(productResult, code: .productReferenceMismatch, valid: 15, invalid: 16)

        guard let firstKind = orderedGroupKinds().first else { throw FixtureError.invalidFixture }
        let missingGroup = copiedInventory(
            base, groups: base.groups.filter { $0.kind != firstKind }
        )
        let groupResult = try assessor.assess(
            podspecJSON: podspec, evidence: freshEvidence(inventory: missingGroup)
        )
        try expectIndexBoundary(groupResult, code: .missingInventoryGroup, valid: 22, invalid: 23)
    }

    @Test("Only bounded decode entry points can decode evidence or portable results")
    func directDecoderBoundaryAndMaximumInventory() throws {
        let evidenceData = try fixtureData("evidence", fileExtension: "json")
        let podspec = try fixturePodspec()
        let evidence = try fixtureEvidence()
        let candidate = try GeneratedPackageBlueprintAssessor().assess(
            podspecJSON: podspec, evidence: evidence
        )
        let candidateData = try candidate.canonicalJSON()
        #expect(throws: GeneratedPackageEvidenceError.invalidEncoding) {
            try JSONDecoder().decode(Evidence.self, from: evidenceData)
        }
        #expect(throws: GeneratedPackageEvidenceError.invalidEncoding) {
            try JSONDecoder().decode(Result.self, from: candidateData)
        }
        let evidenceObject = try JSONObject(data: evidenceData)
        guard let inventoryObject = evidenceObject["inventory"] as? [String: Any] else {
            throw FixtureError.invalidFixture
        }
        #expect(throws: GeneratedPackageEvidenceError.invalidEncoding) {
            try JSONDecoder().decode(Inventory.self, from: jsonData(inventoryObject))
        }
        let candidateObject = try JSONObject(data: candidateData)
        guard let blueprintObject = candidateObject["blueprint"] as? [String: Any] else {
            throw FixtureError.invalidFixture
        }
        #expect(throws: GeneratedPackageEvidenceError.invalidEncoding) {
            try JSONDecoder().decode(GeneratedPackageBlueprint.self, from: jsonData(blueprintObject))
        }

        let base = try fixtureEvidence().inventory
        let maximumSources = generatedSources(count: 256)
        let maximumInventory = copiedInventory(
            base, sources: maximumSources, sourceRoot: "Elsewhere"
        )
        let maximumResult = try GeneratedPackageBlueprintAssessor().assess(
            podspecJSON: podspec, evidence: freshEvidence(inventory: maximumInventory)
        )
        #expect(maximumResult.outcome == .contradictoryEvidence)
        #expect(maximumResult.reasons.contains(.init(code: .selectionCardinalityMismatch, index: nil)))
        #expect(maximumResult.reasons.contains(.init(code: .sourceSelectionMismatch, index: 0)))
        #expect(maximumResult.reasons.contains(.init(code: .ineligibleSource, index: 0)))
        #expect(maximumResult.reasons.contains(.init(code: .targetReferenceMismatch, index: 1)))
        #expect(maximumResult.reasons.contains(.init(code: .sourceRootMismatch, index: 0)))
        #expect(try Result.decodeJSON(try maximumResult.canonicalJSON()) == maximumResult)

        let oversizedInventory = copiedInventory(base, sources: generatedSources(count: 257))
        #expect(throws: GeneratedPackageEvidenceError.limitExceeded) {
            try freshEvidence(inventory: oversizedInventory)
        }
    }

    @Test("Oversized retained v0.5 diagnostics cannot produce an unbounded portable result")
    func resultDiagnosticBudget() throws {
        let frameworks = (0..<4_096).map { "\"Framework\($0)\"" }.joined(separator: ",")
        let podspec = Data(
            ("{\"name\":\"S1Sample\",\"version\":\"1.0.0\",\"source_files\":[\"Sources/Alpha.swift\"],\"frameworks\":[" + frameworks + "]}").utf8
        )
        #expect(throws: GeneratedPackageEvidenceError.limitExceeded) {
            try GeneratedPackageBlueprintAssessor().assess(podspecJSON: podspec, evidence: nil)
        }
    }

    @Test("Generated-package symbols stay isolated to PkgLiftCocoaPods")
    func sourceIsolationRegression() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appending(path: "Sources")
        let enumerator = try #require(
            FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        )
        var violations: [String] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift", !url.path.contains("/PkgLiftCocoaPods/") else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("GeneratedPackageEvidence") || text.contains("GeneratedPackageBlueprint") {
                violations.append(url.path)
            }
        }
        #expect(violations.isEmpty)
    }

    private func fixturePodspec() throws -> Data {
        try fixtureData("S1Sample-1.0.0.podspec", fileExtension: "json")
    }

    private func fixtureEvidence() throws -> Evidence {
        try Evidence.decodeJSON(fixtureData("evidence", fileExtension: "json"))
    }

    private func fixtureData(
        _ name: String, fileExtension: String, subdirectory: String = ""
    ) throws -> Data {
        let directory = "Fixtures/GeneratedPackageS1" + (subdirectory.isEmpty ? "" : "/" + subdirectory)
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: fileExtension, subdirectory: directory
        ))
        return try Data(contentsOf: url)
    }

    private func generatedSources(count: Int) -> [Inventory.Source] {
        (0..<count).map { index in
            Inventory.Source(
                declarationIndex: index,
                path: String(format: "Sources/File%03d.swift", index),
                contentSHA256: digest("content-\(index)"),
                language: index == 0 ? .objectiveC : .swift,
                kind: .regular,
                target: index == 1 ? "Elsewhere" : "S1Sample"
            )
        }
    }

    private func expectIndexBoundary(
        _ result: Result, code: Result.Reason.Code, valid: Int, invalid: Int
    ) throws {
        var object = try JSONObject(data: try result.canonicalJSON())
        object["reasons"] = [["code": code.rawValue, "index": valid]]
        _ = try Result.decodeJSON(try jsonData(object))
        object["reasons"] = [["code": code.rawValue, "index": invalid]]
        #expect(throws: GeneratedPackageEvidenceError.invalidContract) {
            try Result.decodeJSON(try jsonData(object))
        }
    }

    private func freshEvidence(
        inventory: Inventory,
        assessment: PodspecSwiftPMAssessment? = nil,
        podspec: Data? = nil,
        name: String = "S1Sample",
        version: String = "1.0.0",
        snapshotID: String = "s1-snapshot-20260904",
        podspecDigest: String? = nil,
        sourceSnapshotDigest: String? = nil,
        inventoryDigest: String? = nil
    ) throws -> Evidence {
        let actualPodspec: Data
        if let podspec {
            actualPodspec = podspec
        } else {
            actualPodspec = try fixturePodspec()
        }
        let actualAssessment: PodspecSwiftPMAssessment
        if let assessment {
            actualAssessment = assessment
        } else {
            actualAssessment = try GeneratedPackageBlueprintAssessor().assess(
                podspecJSON: actualPodspec, evidence: nil
            ).assessment
        }
        return try Evidence(
            schemaVersion: Evidence.currentSchemaVersion,
            providerProfile: Evidence.syntheticProviderProfile,
            pathProfile: Evidence.canonicalPathProfile,
            snapshot: GeneratedPackageSnapshot(
                name: name, version: version,
                podspecSHA256: podspecDigest ?? sha256(actualPodspec),
                sourceSnapshotID: snapshotID,
                sourceSnapshotSHA256: sourceSnapshotDigest ?? sha256(Data(snapshotID.utf8)),
                inventorySHA256: inventoryDigest ?? (try inventory.canonicalSHA256())
            ),
            assessment: actualAssessment,
            inventory: inventory
        )
    }

    private func copiedInventory(
        _ base: Inventory,
        sourcesComplete: Bool? = nil,
        languagesComplete: Bool? = nil,
        topologyComplete: Bool? = nil,
        sources: [Inventory.Source]? = nil,
        removeConsumer: Bool = false,
        consumer: Inventory.Consumer? = nil,
        removeSourceRoot: Bool = false,
        sourceRoot: String? = nil,
        targets: [Inventory.Target]? = nil,
        products: [Inventory.Product]? = nil,
        groups: [Inventory.Group]? = nil
    ) -> Inventory {
        Inventory(
            sourcesComplete: sourcesComplete ?? base.sourcesComplete,
            languagesComplete: languagesComplete ?? base.languagesComplete,
            topologyComplete: topologyComplete ?? base.topologyComplete,
            sourceRoot: removeSourceRoot ? nil : (sourceRoot ?? base.sourceRoot),
            consumer: removeConsumer ? nil : (consumer ?? base.consumer),
            sources: sources ?? base.sources,
            targets: targets ?? base.targets,
            products: products ?? base.products,
            groups: groups ?? base.groups
        )
    }

    private func orderedGroupKinds() -> [Inventory.Group.Kind] {
        Inventory.Group.Kind.allCases.sorted { $0.rawValue < $1.rawValue }
    }

    private func fixtureJSONObject() throws -> [String: Any] {
        try JSONObject(data: fixtureData("evidence", fileExtension: "json"))
    }

    private func JSONObject(data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.invalidFixture
        }
        return object
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func digest(_ value: String) -> String { sha256(Data(value.utf8)) }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private enum FixtureError: Error {
    case invalidFixture
}
