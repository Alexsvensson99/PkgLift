import Foundation
import PkgLiftCocoaPods

/// Read-only, bounded local file observation with an explicit selection profile.
/// No Ruby, process, network, project discovery or mutation is performed.
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
        inspect(podspecPath: podspecPath, sourceRoot: sourceRoot, sourceSelection: .literalOnly)
    }

    public func inspect(
        podspecPath: String, sourceRoot: String, sourceSelection: LocalSourceSelectionMode
    ) -> LocalSourceInspectionReport {
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
            let selectionReasons = try Self.selectionReasons(for: inspection, mode: sourceSelection)
            var sources: [LocalSourceInspectionReport.Source] = []
            var observations: [(Int, InspectionDirectory.Observation)] = []
            var directories: [(Int, InspectionDirectory.DirectoryObservation)] = []
            if selectionReasons.isEmpty {
                var totalBytes = 0
                let selection = try selectSources(
                    inspection.podspec.root.declarations.sourceFiles,
                    mode: sourceSelection, directory: directory
                )
                directories = selection.directories
                for selected in selection.sources {
                    let index = selected.declarationIndex
                    let path = selected.path
                    currentIndex = index
                    let read = try directory.read(
                        components: path.split(separator: "/").map(String.init),
                        maximumBytes: min(Self.maximumFileBytes, Self.maximumTotalBytes - totalBytes),
                        expectedStamp: selected.stamp,
                        strictByteLimit: sourceSelection == .flatSwiftGlobs,
                        afterChunk: { observer?(.afterSourceChunk(index)) }
                    )
                    if let stamp = selected.stamp, stamp != read.observation.stamp {
                        throw LocalSourceInspectionFailure(.changedDuringRead)
                    }
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
            var enumeratedEntries = 0
            for (index, observation) in directories {
                currentIndex = index
                try directory.validateEntries(
                    observation, maximumEntries: min(4096, 8192 - enumeratedEntries),
                    afterEntry: { observer?(.afterDirectoryEntry(declarationIndex: index, pass: 2)) }
                )
                enumeratedEntries += observation.entryCount
                observer?(.afterDirectoryEnumeration(declarationIndex: index, pass: 2))
            }
            for (index, observation) in observations {
                currentIndex = index
                // In v2 every reread is capped at its original length. The sum is
                // therefore at most the first pass's 64 MiB, including changed files.
                try directory.validate(
                    observation,
                    maximumBytes: sourceSelection == .flatSwiftGlobs ? observation.byteCount : Self.maximumFileBytes,
                    strictByteLimit: sourceSelection == .flatSwiftGlobs
                )
            }
            for (index, observation) in directories {
                currentIndex = index
                try directory.validateDirectoryBinding(observation)
            }
            currentIndex = nil
            try directory.validate()
            try podspecDirectory.validate()

            if !selectionReasons.isEmpty {
                return Self.boundedReport(
                    sourceSelection: sourceSelection, assessment: assessment, podspecSHA256: podspecDigest,
                    status: .unsupportedSelection, sources: [], inventorySHA256: nil,
                    reasons: selectionReasons
                )
            }
            let inventory = LocalSourceInventory(
                schemaVersion: sourceSelection.schemaVersion, providerProfile: sourceSelection.providerProfile,
                pathProfile: sourceSelection.pathProfile, selectionProfile: sourceSelection.selectionProfile,
                podspecSHA256: podspecRead.observation.contentSHA256, sources: sources
            )
            return Self.boundedReport(
                sourceSelection: sourceSelection, assessment: assessment, podspecSHA256: podspecDigest,
                status: .verifiedObservedBytes, sources: sources,
                inventorySHA256: localInspectionSHA256(try localInspectionJSON(inventory)), reasons: []
            )
        } catch {
            let failure = error as? LocalSourceInspectionFailure
            let code = failure?.code ?? .unreadableInput
            return Self.boundedReport(
                sourceSelection: sourceSelection, assessment: assessment, podspecSHA256: podspecDigest,
                status: .unavailable, sources: [], inventorySHA256: nil,
                reasons: [.init(code: code, declarationIndex: currentIndex ?? failure?.declarationIndex)]
            )
        }
    }

    private static func selectionReasons(
        for inspection: PodspecInspection, mode: LocalSourceSelectionMode
    ) throws -> [LocalSourceInspectionReport.Reason] {
        let root = inspection.podspec.root
        let paths = root.declarations.sourceFiles
        guard paths.count <= maximumSources else { throw LocalSourceInspectionFailure(.limitExceeded) }
        var seen: Set<String> = []
        var reasons: [LocalSourceInspectionReport.Reason] = []
        for (index, path) in paths.enumerated() {
            try InspectionSourcePath.validate(path, declarationIndex: index, mode: mode)
            guard seen.insert(path.lowercased()).inserted else {
                throw LocalSourceInspectionFailure(.duplicateSourcePath, declarationIndex: index)
            }
            if InspectionSourcePath.containsPattern(path) {
                if mode == .literalOnly || InspectionSourcePath.flatGlobDirectory(path) == nil {
                    reasons.append(.init(code: .unsupportedGlob, declarationIndex: index))
                }
            } else if !path.hasSuffix(".swift") {
                reasons.append(.init(code: .unsupportedSourceType, declarationIndex: index))
            }
        }
        if mode == .flatSwiftGlobs {
            let directories = Set(paths.compactMap(InspectionSourcePath.flatGlobDirectory).map { $0.joined(separator: "/") })
            guard directories.count <= 16 else { throw LocalSourceInspectionFailure(.limitExceeded) }
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

    private struct SelectedSource {
        let declarationIndex: Int
        let path: String
        let stamp: InspectionFileStamp?
    }

    private struct Selection {
        var sources: [SelectedSource] = []
        var directories: [(Int, InspectionDirectory.DirectoryObservation)] = []
    }

    private func selectSources(
        _ paths: [String], mode: LocalSourceSelectionMode, directory: InspectionDirectory
    ) throws -> Selection {
        var selection = Selection()
        var seen: Set<String> = []
        var enumeratedEntries = 0
        for (index, path) in paths.enumerated() {
            do {
                if mode == .flatSwiftGlobs, let components = InspectionSourcePath.flatGlobDirectory(path) {
                    let observation = try directory.observeEntries(
                        components: components, maximumEntries: min(4096, 8192 - enumeratedEntries),
                        afterEntry: { observer?(.afterDirectoryEntry(declarationIndex: index, pass: 1)) }
                    )
                    enumeratedEntries += observation.entryCount
                    selection.directories.append((index, observation))
                    observer?(.afterDirectoryEnumeration(declarationIndex: index, pass: 1))
                    var matches = 0
                    for entry in observation.entries where InspectionSourcePath.matchesFlatSwiftName(entry.nameBytes) {
                        let matched = try InspectionSourcePath.matchedPath(
                            directory: components, nameBytes: entry.nameBytes, declarationIndex: index
                        )
                        guard !entry.stamp.isSymlink else { throw LocalSourceInspectionFailure(.symbolicLink) }
                        guard entry.stamp.isRegular else { throw LocalSourceInspectionFailure(.nonRegularFile) }
                        try appendSource(matched, index: index, stamp: entry.stamp, to: &selection, seen: &seen)
                        matches += 1
                    }
                    guard matches > 0 else { throw LocalSourceInspectionFailure(.noSourceMatches) }
                } else {
                    try appendSource(path, index: index, stamp: nil, to: &selection, seen: &seen)
                }
            } catch {
                throw LocalSourceInspectionFailure(
                    (error as? LocalSourceInspectionFailure)?.code ?? .unreadableInput,
                    declarationIndex: index
                )
            }
        }
        return selection
    }

    private func appendSource(
        _ path: String, index: Int, stamp: InspectionFileStamp?,
        to selection: inout Selection, seen: inout Set<String>
    ) throws {
        guard seen.insert(path.lowercased()).inserted else {
            throw LocalSourceInspectionFailure(.duplicateSourcePath)
        }
        guard selection.sources.count < Self.maximumSources else { throw LocalSourceInspectionFailure(.limitExceeded) }
        selection.sources.append(.init(declarationIndex: index, path: path, stamp: stamp))
    }

    private static func boundedReport(
        sourceSelection: LocalSourceSelectionMode,
        assessment: PodspecSwiftPMAssessment?, podspecSHA256: String?,
        status: LocalSourceInspectionReport.Status, sources: [LocalSourceInspectionReport.Source],
        inventorySHA256: String?, reasons: [LocalSourceInspectionReport.Reason]
    ) -> LocalSourceInspectionReport {
        let report = LocalSourceInspectionReport(
            sourceSelection: sourceSelection, assessment: assessment, podspecSHA256: podspecSHA256, status: status,
            sources: sources, inventorySHA256: inventorySHA256, reasons: reasons
        )
        guard (try? report.canonicalJSON()) != nil else {
            // An oversized diagnostic cannot bypass the output budget by being
            // attached to an error. Preserve the exact-byte binding and refuse.
            return LocalSourceInspectionReport(
                sourceSelection: sourceSelection, assessment: nil, podspecSHA256: podspecSHA256, status: .unavailable,
                sources: [], inventorySHA256: nil,
                reasons: [.init(code: .limitExceeded, declarationIndex: nil)]
            )
        }
        return report
    }
}

private struct LocalSourceInventory: Encodable {
    let schemaVersion: Int
    let providerProfile: String
    let pathProfile: String
    let selectionProfile: String?
    let podspecSHA256: String
    let sources: [LocalSourceInspectionReport.Source]
}
