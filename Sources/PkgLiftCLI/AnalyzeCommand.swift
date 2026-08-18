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

    @Option(
        name: .customLong("fail-on"),
        help: "Exit 1 after analysis when direct dependencies meet blocked, unresolved, or non-auto policy."
    )
    var failOn: AnalyzeFailurePolicy?

    mutating func validate() throws {
        if common.json && portableJSON {
            throw ValidationError("--json and --portable-json are mutually exclusive.")
        }
    }

    mutating func run() async throws {
        let context = try await CommandContext.load(from: common)
        let analysis = context.buildProjectAnalysis()

        if common.json || portableJSON {
            print(try Self.jsonOutput(for: analysis, portable: portableJSON))
        } else {
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
                if let details = candidate.reasonDetails, !details.isEmpty {
                    for reason in details {
                        print("  - [\(reason.code.rawValue)] \(reason.message)")
                        if let remediation = reason.remediation {
                            print("    Next: \(remediation)")
                        }
                    }
                } else {
                    for reason in candidate.reasons {
                        print("  - \(reason)")
                    }
                }
            }
        }

        if let failOn {
            let failingCandidates = failOn.failingDirectCandidates(in: analysis.candidates)
            if !failingCandidates.isEmpty {
                throw AnalysisError.failurePolicyMatched(
                    policy: failOn,
                    dependencyCount: failingCandidates.count
                )
            }
        }
    }

    static func jsonOutput(for analysis: ProjectAnalysis, portable: Bool) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(analysis)
        let output = try PortableJSON().output(from: data, portable: portable)
        guard let json = String(data: output, encoding: .utf8) else {
            throw AnalysisError.encodingFailed
        }
        return json
    }
}

enum AnalyzeFailurePolicy: String, ExpressibleByArgument, CaseIterable, Sendable {
    case blocked
    case unresolved
    case nonAuto = "non-auto"

    func failingDirectCandidates(in candidates: [MigrationCandidate]) -> [MigrationCandidate] {
        candidates.filter { candidate in
            guard candidate.pod.isDirect else { return false }
            switch self {
            case .blocked:
                return candidate.classification == .blocked
            case .unresolved:
                return candidate.classification == .blocked || candidate.classification == .unknown
            case .nonAuto:
                return candidate.classification != .auto
            }
        }
    }
}

enum AnalysisError: LocalizedError {
    case encodingFailed
    case failurePolicyMatched(policy: AnalyzeFailurePolicy, dependencyCount: Int)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode analysis output as JSON."
        case .failurePolicyMatched(let policy, let dependencyCount):
            return "Analysis completed, but --fail-on \(policy.rawValue) matched \(dependencyCount) direct dependency candidate(s)."
        }
    }
}
