import CryptoKit
import Foundation
import PkgLiftCocoaPods

/// Output only: observed local bytes never authorize package generation or migration.
/// There is deliberately no decoder or public memberwise initializer for this report.
public struct LocalSourceInspectionReport: Sendable, Encodable {
    public enum Status: String, Sendable, Encodable {
        case verifiedObservedBytes, unsupportedSelection, unavailable
    }

    public struct Source: Sendable, Encodable, Equatable {
        public let declarationIndex: Int
        public let pathSHA256: String
        public let contentSHA256: String
        public let byteCount: Int
    }

    public struct Reason: Sendable, Encodable, Equatable {
        public enum Code: String, Sendable, Encodable {
            case invalidInputPath, invalidPodspec, invalidSourcePath
            case missingInput, unreadableInput, nonRegularFile, symbolicLink
            case limitExceeded, changedDuringRead
            case missingSourceSelection, unsupportedGlob, unsupportedSourceType
            case ambiguousScope, excludedSources, unknownSelectionSemantics
            case duplicateSourcePath, noSourceMatches
        }

        public let code: Code
        public let declarationIndex: Int?
    }

    public let schemaVersion: Int
    public let providerProfile: String
    public let selectionProfile: String?
    public let pathProfile: String
    public let origin: String = "notVerified"
    public let selectionCoverage: String = "declaredRootSourcesOnly"
    public let packageValidity: String = "notAssessed"
    public let migrationEligibility: String = "notAssessed"
    public let assessment: PodspecSwiftPMAssessment?
    public let podspecSHA256: String?
    public let status: Status
    public let sources: [Source]
    public let inventorySHA256: String?
    public let reasons: [Reason]

    init(
        sourceSelection: LocalSourceSelectionMode = .literalOnly,
        assessment: PodspecSwiftPMAssessment?, podspecSHA256: String?,
        status: Status, sources: [Source], inventorySHA256: String?, reasons: [Reason]
    ) {
        schemaVersion = sourceSelection.schemaVersion
        pathProfile = sourceSelection.pathProfile
        providerProfile = sourceSelection.providerProfile
        selectionProfile = sourceSelection.selectionProfile
        self.assessment = assessment
        self.podspecSHA256 = podspecSHA256
        self.status = status
        self.sources = sources
        self.inventorySHA256 = inventorySHA256
        self.reasons = reasons
    }

    public var exitCode: Int32 { status == .unavailable ? 1 : 0 }

    /// A fixed, privacy-bounded schema. No raw input paths, values or timestamps.
    public func canonicalJSON() throws -> Data {
        let data = try localInspectionJSON(self)
        guard data.count <= PodspecInspectionLimits.default.maximumJSONBytes else {
            throw LocalSourceInspectionFailure(.limitExceeded)
        }
        return data
    }
}

struct LocalSourceInspectionFailure: Error, Sendable {
    let code: LocalSourceInspectionReport.Reason.Code
    let declarationIndex: Int?

    init(_ code: LocalSourceInspectionReport.Reason.Code, declarationIndex: Int? = nil) {
        self.code = code
        self.declarationIndex = declarationIndex
    }
}

/// Internal observation seams can mutate test fixtures, but cannot skip validation.
enum LocalSourceInspectionEvent: Sendable, Equatable {
    case afterPodspecRead
    case afterSourceChunk(Int)
    case afterSourceRead(Int)
    case beforeFinalValidation
    case afterDirectoryEntry(declarationIndex: Int, pass: Int)
    case afterDirectoryEnumeration(declarationIndex: Int, pass: Int)
}

func localInspectionJSON(_ value: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(value)
}

func localInspectionSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
