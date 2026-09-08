//
//  PodspecCommand.swift
//  PkgLiftCLI
//

import ArgumentParser
import Foundation
import PkgLiftInspection

/// Commands that operate on an explicitly supplied Podspec JSON document.
struct PodspecCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "podspec",
        abstract: "Inspect an explicitly supplied Podspec JSON document.",
        subcommands: [PodspecInspectCommand.self]
    )
}

/// Reports the bytes observed for a supported literal root `source_files` selection.
///
/// This command intentionally has no project options: it does not discover a project,
/// invoke CocoaPods, resolve network sources, or write files.
struct PodspecInspectCommand: AsyncParsableCommand {
    enum OutputFormat: String, ExpressibleByArgument {
        case text
        case json
    }

    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect explicit local source bytes referenced by a Podspec JSON document."
    )

    @Option(
        name: .customLong("podspec"),
        help: "Path to an existing Podspec JSON document."
    )
    var podspecPath: String

    @Option(
        name: .customLong("source-root"),
        help: "Path to the local source directory to inspect."
    )
    var sourceRoot: String

    @Option(
        name: .customLong("format"),
        help: "Report format: text (default) or json."
    )
    var format: OutputFormat = .text

    mutating func run() async throws {
        let report = LocalSourceInspector().inspect(
            podspecPath: podspecPath,
            sourceRoot: sourceRoot
        )

        do {
            print(try Self.render(report, format: format))
        } catch {
            // Do not let an implementation error expose a caller-supplied path or
            // local filesystem diagnostic through ArgumentParser's stderr output.
            throw PodspecCommandError.unavailableReportEncoding
        }

        if report.exitCode != 0 {
            throw ExitCode.failure
        }
    }

    /// Kept separate from `run()` so tests can inspect report text without changing
    /// process-global stdout.
    static func render(
        _ report: LocalSourceInspectionReport,
        format: OutputFormat
    ) throws -> String {
        switch format {
        case .json:
            return String(decoding: try report.canonicalJSON(), as: UTF8.self)
        case .text:
            return textReport(for: report)
        }
    }

    private static func textReport(for report: LocalSourceInspectionReport) -> String {
        var lines = [
            "Local source inspection: \(statusName(report.status))",
            "Origin: \(report.origin)",
            "Selection coverage: \(report.selectionCoverage)",
            "Package validity: \(report.packageValidity)",
            "Migration eligibility: \(report.migrationEligibility)",
        ]

        if let assessment = report.assessment {
            lines.append("Declaration assessment: \(assessment.outcome.rawValue)")
            if assessment.reasons.isEmpty {
                lines.append("Declaration reasons: none")
            } else {
                lines.append("Declaration reasons:")
                lines.append(contentsOf: assessment.reasons.map {
                    "  - [\($0.code.rawValue)] \($0.evidencePath)"
                })
            }
        } else {
            lines.append("Declaration assessment: unavailable")
        }

        if let digest = report.podspecSHA256 {
            lines.append("Podspec SHA-256: \(digest)")
        }

        if report.sources.isEmpty {
            lines.append("Observed sources: none")
        } else {
            lines.append("Observed sources:")
            lines.append(contentsOf: report.sources.map { source in
                "  - declaration #\(source.declarationIndex): \(source.byteCount) bytes; "
                    + "path SHA-256: \(source.pathSHA256); content SHA-256: \(source.contentSHA256)"
            })
        }

        if report.reasons.isEmpty {
            lines.append("Inspection reasons: none")
        } else {
            lines.append("Inspection reasons:")
            lines.append(contentsOf: report.reasons.map { reason in
                if let declarationIndex = reason.declarationIndex {
                    return "  - [\(reason.code.rawValue)] declaration #\(declarationIndex)"
                }
                return "  - [\(reason.code.rawValue)]"
            })
        }

        if let digest = report.inventorySHA256 {
            lines.append("Inventory SHA-256: \(digest)")
        }

        lines.append(
            "Observed bytes do not establish SwiftPM compatibility, provenance, or migration approval."
        )
        return lines.joined(separator: "\n")
    }

    private static func statusName(_ status: LocalSourceInspectionReport.Status) -> String {
        switch status {
        case .verifiedObservedBytes:
            return "verifiedObservedBytes"
        case .unsupportedSelection:
            return "unsupportedSelection"
        case .unavailable:
            return "unavailable"
        }
    }
}

private enum PodspecCommandError: LocalizedError {
    case unavailableReportEncoding

    var errorDescription: String? {
        switch self {
        case .unavailableReportEncoding:
            return "The local source inspection report could not be encoded."
        }
    }
}
