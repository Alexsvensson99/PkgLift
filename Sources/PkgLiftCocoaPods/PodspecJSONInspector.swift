// PkgLiftCocoaPods/PodspecJSONInspector.swift
// Offline, in-memory inspection of bounded Podspec JSON semantics.

import Foundation

/// Inspects already available `.podspec.json` data without executing Ruby,
/// reading files, resolving globs, starting processes, or contacting a network.
public struct PodspecJSONInspector: Sendable {
    private let semanticProfile: CocoaPodsSemanticProfile
    private let limits: PodspecInspectionLimits

    public init(
        semanticProfile: CocoaPodsSemanticProfile = .cocoaPodsCore1_17_0,
        limits: PodspecInspectionLimits = .default
    ) {
        self.semanticProfile = semanticProfile
        self.limits = limits
    }

    public func inspect(json data: Data) throws -> PodspecInspection {
        try validateSemanticProfile()
        try validateLimits()
        guard data.count <= limits.maximumJSONBytes else {
            throw PodspecInspectionError.inputExceedsLimit(
                actual: data.count,
                maximum: limits.maximumJSONBytes
            )
        }

        var boundaryScanner = PodspecJSONBoundaryScanner(data: data, limits: limits)
        try boundaryScanner.validate()

        let rawRoot: Any
        do {
            rawRoot = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw PodspecInspectionError.malformedJSON
        }

        guard let root = rawRoot as? [String: Any] else {
            throw PodspecInspectionError.rootMustBeObject(path: "")
        }

        var decoder = PodspecSemanticDecoder()
        let decoded = try decoder.decode(root)
        return PodspecInspection(
            podspec: PodspecSemanticModel(
                semanticProfile: semanticProfile,
                version: decoded.version,
                root: decoded.root
            ),
            unsupportedFields: decoded.unsupportedFields
        )
    }

    private func validateSemanticProfile() throws {
        guard semanticProfile == .cocoaPodsCore1_17_0 else {
            throw PodspecInspectionError.unsupportedSemanticProfile(
                identifier: semanticProfile.identifier
            )
        }
    }

    private func validateLimits() throws {
        let positiveLimits = [
            ("maximumJSONBytes", limits.maximumJSONBytes),
            ("maximumContainerElements", limits.maximumContainerElements),
            ("maximumTotalValues", limits.maximumTotalValues),
            ("maximumStringUTF8Bytes", limits.maximumStringUTF8Bytes),
        ]
        if let invalid = positiveLimits.first(where: { $0.1 < 1 }) {
            throw PodspecInspectionError.invalidLimit(
                name: invalid.0,
                value: invalid.1
            )
        }
        guard limits.maximumNestingDepth >= 0,
              limits.maximumNestingDepth <= PodspecInspectionLimits.maximumSupportedNestingDepth else {
            throw PodspecInspectionError.invalidLimit(
                name: "maximumNestingDepth",
                value: limits.maximumNestingDepth
            )
        }
    }
}
