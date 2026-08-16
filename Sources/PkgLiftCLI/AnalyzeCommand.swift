//
//  AnalyzeCommand.swift
//  PkgLiftCLI
//

import ArgumentParser
import Foundation
import PkgLiftCore

struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "analyze", abstract: "Analyze project dependencies.")

    @OptionGroup var common: CommonOptions

    @Flag(
        name: .customLong("portable-json"),
        help: "Output shareable JSON with local paths and URL secrets redacted."
    )
    var portableJSON: Bool = false

    mutating func validate() throws {
        if common.json && portableJSON {
            throw ValidationError("--json and --portable-json are mutually exclusive.")
        }
    }

    mutating func run() async throws {
        let context = try await CommandContext.load(from: common)
        let analysis = context.buildProjectAnalysis()

        if common.json || portableJSON {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(analysis)
            let output = try PortableJSON().output(from: data, portable: portableJSON)
            guard let json = String(data: output, encoding: .utf8) else {
                throw AnalysisError.encodingFailed
            }
            print(json)
            return
        }

        print("Project: \(analysis.project.projectPath)")
        print("Readiness score: \(analysis.readinessScore)/100")
        let directDependencyCount = analysis.counts?.uniqueDirectDependencyCount
            ?? analysis.cocoaPods.directDependencies.count
        print("Direct dependencies: \(directDependencyCount)")
        if let counts = analysis.counts,
           counts.literalPodfileDeclarationCount != counts.uniqueDirectDependencyCount {
            print("Literal Podfile declarations: \(counts.literalPodfileDeclarationCount)")
        }
        print("Transitive dependencies: \(analysis.cocoaPods.transitiveDependencies.count)")
        print("Podfile detected: \(analysis.cocoaPods.hasPodfile ? "yes" : "no")")
        print("Podfile.lock detected: \(analysis.cocoaPods.hasPodfileLock ? "yes" : "no")")
        print("SwiftPM packages: \(analysis.swiftPM.packages.count)")

        print("\nMigration candidates:")

        let sortedCandidates = analysis.candidates.sorted { lhs, rhs in
            if lhs.classification.rawValue == rhs.classification.rawValue {
                return lhs.pod.name.lowercased() < rhs.pod.name.lowercased()
            }
            return lhs.classification.rawValue < rhs.classification.rawValue
        }

        for candidate in sortedCandidates {
            print("- \(candidate.classification.rawValue): \(candidate.pod.name)")
            if let mappedPackage = candidate.packageCandidate {
                print("  → \(mappedPackage.repositoryURL)")
            }
            for issue in candidate.issues {
                print("  - \(issue.severity.rawValue): \(issue.message)")
            }
        }
    }
}

private enum AnalysisError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode analysis output as JSON."
        }
    }
}
