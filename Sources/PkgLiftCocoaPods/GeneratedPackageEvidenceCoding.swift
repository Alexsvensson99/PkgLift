import Foundation

func generatedPackageEncode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

func generatedPackageDecode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
    guard data.count <= PodspecInspectionLimits.default.maximumJSONBytes else {
        throw GeneratedPackageEvidenceError.limitExceeded
    }
    do {
        var scanner = PodspecJSONBoundaryScanner(data: data, limits: .default)
        try scanner.validate()
        let decoder = JSONDecoder()
        guard let key = generatedPackageBoundaryKey else {
            throw GeneratedPackageEvidenceError.invalidEncoding
        }
        decoder.userInfo[key] = GeneratedPackageDecodingToken()
        return try decoder.decode(type, from: data)
    } catch let error as GeneratedPackageEvidenceError {
        throw error
    } catch {
        throw GeneratedPackageEvidenceError.invalidEncoding
    }
}

private final class GeneratedPackageDecodingToken: Sendable {}
private let generatedPackageBoundaryKey = CodingUserInfoKey(
    rawValue: "PkgLiftCocoaPods.GeneratedPackage.bounded-decoding"
)

func generatedPackageRequireDecodingBoundary(_ decoder: Decoder) throws {
    guard let key = generatedPackageBoundaryKey,
          decoder.userInfo[key] is GeneratedPackageDecodingToken else {
        throw GeneratedPackageEvidenceError.invalidEncoding
    }
}

/// Every returned assessment must fit the same byte, collection and nesting budget as
/// its decoder, including diagnostics retained from the original v0.5 assessment.
func generatedPackageCheckEncodedBounds<T: Encodable>(_ value: T) throws {
    let data = try generatedPackageEncode(value)
    guard data.count <= PodspecInspectionLimits.default.maximumJSONBytes else {
        throw GeneratedPackageEvidenceError.limitExceeded
    }
    do {
        var scanner = PodspecJSONBoundaryScanner(data: data, limits: .default)
        try scanner.validate()
    } catch {
        throw GeneratedPackageEvidenceError.limitExceeded
    }
}

/// Inspect the same decoder before typed decoding so nested unknown keys and omitted
/// nullable fields cannot disappear through synthesized Decodable behavior.
indirect enum GeneratedPackageJSONShape: Sendable {
    case value
    case object([String: GeneratedPackageJSONShape])
    case array(GeneratedPackageJSONShape)
    case nullable(GeneratedPackageJSONShape)
}

private struct GeneratedPackageJSONKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

func generatedPackageCheckShape(_ decoder: Decoder, shape: GeneratedPackageJSONShape) throws {
    switch shape {
    case .value:
        return
    case .nullable(let child):
        if try decoder.singleValueContainer().decodeNil() { return }
        try generatedPackageCheckShape(decoder, shape: child)
    case .array(let child):
        var container = try decoder.unkeyedContainer()
        var count = 0
        while !container.isAtEnd {
            count += 1
            guard count <= 4_096 else { throw GeneratedPackageEvidenceError.limitExceeded }
            try generatedPackageCheckShape(container.superDecoder(), shape: child)
        }
    case .object(let fields):
        let container = try decoder.container(keyedBy: GeneratedPackageJSONKey.self)
        guard Set(container.allKeys.map(\.stringValue)) == Set(fields.keys) else {
            throw GeneratedPackageEvidenceError.invalidEncoding
        }
        for key in container.allKeys {
            guard let child = fields[key.stringValue] else {
                throw GeneratedPackageEvidenceError.invalidEncoding
            }
            try generatedPackageCheckShape(container.superDecoder(forKey: key), shape: child)
        }
    }
}

extension GeneratedPackageJSONShape {
    static func fields(_ names: [String]) -> Self {
        .object(Dictionary(uniqueKeysWithValues: names.map { ($0, .value) }))
    }

    static let assessment: Self = .object([
        "schemaVersion": .value, "cocoaPodsProfile": .value, "swiftPMProfile": .value,
        "outcome": .value,
        "reasons": .array(.fields(["code", "evidencePath"])),
    ])

    static let consumer: Self = .fields(["platform", "minimumVersion", "languageProfile"])

    static let blueprint: Self = .object([
        "shapeProfile": .value, "identitySHA256": .value, "versionSHA256": .value,
        "sourceRootSHA256": .value, "consumer": .consumer,
        "sources": .array(.fields(["declarationIndex", "pathSHA256", "contentSHA256"])),
    ])

    static let inventory: Self = .object([
        "sourcesComplete": .value, "languagesComplete": .value, "topologyComplete": .value,
        "sourceRoot": .nullable(.value), "consumer": .nullable(.consumer),
        "sources": .array(.fields([
            "declarationIndex", "path", "contentSHA256", "language", "kind", "target",
        ])),
        "targets": .array(.fields(["name", "kind"])),
        "products": .array(.object([
            "name": .value, "kind": .value, "targets": .array(.value),
        ])),
        "groups": .array(.object([
            "kind": .value, "complete": .value, "entries": .array(.value),
        ])),
    ])
}

extension GeneratedPackageEvidence {
    static let jsonShape: GeneratedPackageJSONShape = .object([
        "schemaVersion": .value, "providerProfile": .value, "pathProfile": .value,
        "snapshot": .fields([
            "name", "version", "podspecSHA256", "sourceSnapshotID",
            "sourceSnapshotSHA256", "inventorySHA256",
        ]),
        "assessment": .assessment,
        "inventory": .inventory,
    ])
}
