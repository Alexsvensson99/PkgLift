import Foundation
import PkgLiftCocoaPods

/// Read-only, bounded local file observation. No Ruby, glob expansion, process,
/// network, project discovery or mutation is performed by this adapter.
public struct LocalSourceInspector: Sendable {
    private let observer: (@Sendable (LocalSourceInspectionEvent) -> Void)?
    private static let maximumSources = 256
    private static let maximumFileBytes = 16 * 1_024 * 1_024
    private static let maximumTotalBytes = 64 * 1_024 * 1_024

    public init() { observer = nil }

    init(observer: @escaping @Sendable (LocalSourceInspectionEvent) -> Void) {
        self.observer = observer
    }

    public func inspect(podspecPath: String, sourceRoot: String) -> LocalSourceInspectionReport {
        var assessment: PodspecSwiftPMAssessment?
        var podspecDigest: String?
        var currentIndex: Int?
        do {
            let input = try InspectionInputPath(podspecPath)
            guard let filename = input.components.last else {
                throw LocalSourceInspectionFailure(.invalidInputPath)
            }
            let podspecDirectory = try InspectionDirectory(
                isAbsolute: input.isAbsolute, components: Array(input.components.dropLast())
            )
            let jsonLimit = PodspecInspectionLimits.default.maximumJSONBytes
            let podspecRead = try podspecDirectory.read(
                components: [filename], maximumBytes: jsonLimit, captureBytes: true
            )
            podspecDigest = podspecRead.observation.contentSHA256
            observer?(.afterPodspecRead)

            let inspection: PodspecInspection
            do {
                inspection = try PodspecJSONInspector().inspect(json: podspecRead.bytes)
                assessment = try PodspecSwiftPMAssessor().assess(
                    inspection, cocoaPodsProfile: .cocoaPodsCore1_17_0,
                    swiftPMProfile: .swiftToolsVersion6_0
                )
            } catch {
                throw LocalSourceInspectionFailure(.invalidPodspec)
            }

            let rootPath = try InspectionInputPath(sourceRoot)
            let directory = try InspectionDirectory(isAbsolute: rootPath.isAbsolute, components: rootPath.components)
            let selectionReasons = try Self.selectionReasons(for: inspection)
            var sources: [LocalSourceInspectionReport.Source] = []
            var observations: [(Int, InspectionDirectory.Observation)] = []
            if selectionReasons.isEmpty {
                var totalBytes = 0
                for (index, path) in inspection.podspec.root.declarations.sourceFiles.enumerated() {
                    currentIndex = index
                    let read = try directory.read(
                        components: path.split(separator: "/").map(String.init),
                        maximumBytes: min(Self.maximumFileBytes, Self.maximumTotalBytes - totalBytes),
                        afterChunk: { observer?(.afterSourceChunk(index)) }
                    )
                    totalBytes += read.observation.byteCount
                    observations.append((index, read.observation))
                    sources.append(.init(
                        declarationIndex: index,
                        pathSHA256: localInspectionSHA256(Data(path.utf8)),
                        contentSHA256: read.observation.contentSHA256,
                        byteCount: read.observation.byteCount
                    ))
                    observer?(.afterSourceRead(index))
                }
            }
            currentIndex = nil
            observer?(.beforeFinalValidation)
            try directory.validate()
            try podspecDirectory.validate()
            try podspecDirectory.validate(podspecRead.observation, maximumBytes: jsonLimit)
            for (index, observation) in observations {
                currentIndex = index
                try directory.validate(observation, maximumBytes: Self.maximumFileBytes)
            }
            currentIndex = nil
            try directory.validate()
            try podspecDirectory.validate()

            if !selectionReasons.isEmpty {
                return Self.boundedReport(
                    assessment: assessment, podspecSHA256: podspecDigest,
                    status: .unsupportedSelection, sources: [], inventorySHA256: nil,
                    reasons: selectionReasons
                )
            }
            let inventory = LocalSourceInventory(podspecSHA256: podspecRead.observation.contentSHA256, sources: sources)
            return Self.boundedReport(
                assessment: assessment, podspecSHA256: podspecDigest,
                status: .verifiedObservedBytes, sources: sources,
                inventorySHA256: localInspectionSHA256(try localInspectionJSON(inventory)), reasons: []
            )
        } catch {
            let failure = error as? LocalSourceInspectionFailure
            let code = failure?.code ?? .unreadableInput
            return Self.boundedReport(
                assessment: assessment, podspecSHA256: podspecDigest,
                status: .unavailable, sources: [], inventorySHA256: nil,
                reasons: [.init(code: code, declarationIndex: currentIndex ?? failure?.declarationIndex)]
            )
        }
    }

    private static func selectionReasons(for inspection: PodspecInspection) throws -> [LocalSourceInspectionReport.Reason] {
        let root = inspection.podspec.root
        let paths = root.declarations.sourceFiles
        guard paths.count <= maximumSources else { throw LocalSourceInspectionFailure(.limitExceeded) }
        var seen: Set<String> = []
        var reasons: [LocalSourceInspectionReport.Reason] = []
        for (index, path) in paths.enumerated() {
            guard path.utf8.count <= 512 else {
                throw LocalSourceInspectionFailure(.limitExceeded, declarationIndex: index)
            }
            guard !path.isEmpty, !path.hasPrefix("/"),
                  path.utf8.allSatisfy({
                      (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                          || [UInt8(95), 46, 45, 47, 42, 63, 91, 93, 123, 125].contains($0)
                  }) else { throw LocalSourceInspectionFailure(.invalidSourcePath, declarationIndex: index) }
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw LocalSourceInspectionFailure(.invalidSourcePath, declarationIndex: index)
            }
            guard seen.insert(path.lowercased()).inserted else {
                throw LocalSourceInspectionFailure(.duplicateSourcePath, declarationIndex: index)
            }
            if path.contains(where: { "*?[]{}".contains($0) }) {
                reasons.append(.init(code: .unsupportedGlob, declarationIndex: index))
            } else if !path.hasSuffix(".swift") {
                reasons.append(.init(code: .unsupportedSourceType, declarationIndex: index))
            }
        }
        // Validate the entire declared root list before reporting an unsupported
        // shape: an early glob must not hide a later traversal, duplicate or limit.
        if !root.subspecs.isEmpty || root.defaultSubspecs != .implicitAll || !root.platformScopes.isEmpty {
            reasons.append(.init(code: .ambiguousScope, declarationIndex: nil))
        }
        if !root.declarations.compilation.excludeFiles.isEmpty {
            reasons.append(.init(code: .excludedSources, declarationIndex: nil))
        }
        // Only the ordinary root source declaration is known to be unrelated to
        // interpreting this literal list. Retain its original assessment reason.
        if inspection.unsupportedFields.contains(where: { $0.path != "/source" || $0.kind != .deferredCocoaPodsSemantic }) {
            reasons.append(.init(code: .unknownSelectionSemantics, declarationIndex: nil))
        }
        if paths.isEmpty { reasons.append(.init(code: .missingSourceSelection, declarationIndex: nil)) }
        return reasons.sorted {
            if $0.code.rawValue != $1.code.rawValue { return $0.code.rawValue < $1.code.rawValue }
            return ($0.declarationIndex ?? -1) < ($1.declarationIndex ?? -1)
        }
    }

    private static func boundedReport(
        assessment: PodspecSwiftPMAssessment?, podspecSHA256: String?,
        status: LocalSourceInspectionReport.Status, sources: [LocalSourceInspectionReport.Source],
        inventorySHA256: String?, reasons: [LocalSourceInspectionReport.Reason]
    ) -> LocalSourceInspectionReport {
        let report = LocalSourceInspectionReport(
            assessment: assessment, podspecSHA256: podspecSHA256, status: status,
            sources: sources, inventorySHA256: inventorySHA256, reasons: reasons
        )
        guard (try? report.canonicalJSON()) != nil else {
            // An oversized diagnostic cannot bypass the output budget by being
            // attached to an error. Preserve the exact-byte binding and refuse.
            return LocalSourceInspectionReport(
                assessment: nil, podspecSHA256: podspecSHA256, status: .unavailable,
                sources: [], inventorySHA256: nil,
                reasons: [.init(code: .limitExceeded, declarationIndex: nil)]
            )
        }
        return report
    }
}

private struct LocalSourceInventory: Encodable {
    let schemaVersion = 1
    let providerProfile = "pkglift.local-source-inspection/v1"
    let pathProfile = "ascii-relative-path/v1"
    let podspecSHA256: String
    let sources: [LocalSourceInspectionReport.Source]
}
