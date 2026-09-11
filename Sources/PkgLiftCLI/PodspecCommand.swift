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
            summary(for: report),
            "Local source inspection: \(statusName(report.status))",
            "Origin: \(report.origin)",
            "Selection coverage: \(report.selectionCoverage)",
            "Package validity: \(report.packageValidity)",
            "Migration eligibility: \(report.migrationEligibility)",
        ]

        if report.reasons.isEmpty {
            lines.append("Inspection reasons: none")
        } else {
            lines.append("Inspection reasons:")
            lines.append(contentsOf: report.reasons.map { reason in
                if let declarationIndex = reason.declarationIndex {
                    return "  - [\(reason.code.rawValue)] declaration #\(declarationIndex) (zero-based source_files index): \(explanation(for: reason.code))"
                }
                return "  - [\(reason.code.rawValue)] \(explanation(for: reason.code))"
            })
        }

        lines.append(nextStep(for: report.status))
        lines.append("File observation and declaration compatibility are separate results; neither approves migration.")

        if let assessment = report.assessment {
            lines.append("Declaration assessment: \(assessment.outcome.rawValue)")
            if assessment.reasons.isEmpty {
                lines.append("Declaration reasons: none")
            } else {
                lines.append("Declaration reasons (separate from file inspection):")
                lines.append("  Evidence paths refer to the normalized assessment; /unsupportedFields/N is an assessment index, not an original JSON field name.")
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
            lines.append("Observed sources: none reported; this does not mean the project has no source files.")
        } else {
            lines.append("Observed sources:")
            lines.append(contentsOf: report.sources.map { source in
                "  - declaration #\(source.declarationIndex): \(source.byteCount) bytes; "
                    + "path SHA-256: \(source.pathSHA256); content SHA-256: \(source.contentSHA256)"
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

    private static func summary(for report: LocalSourceInspectionReport) -> String {
        switch report.status {
        case .verifiedObservedBytes:
            return "Observed and hashed \(report.sources.count) declared root Swift source file(s)."
        case .unsupportedSelection:
            return "Source selection is not supported. No source-file inventory was produced."
        case .unavailable:
            return "Inspection could not complete. No partial source-file inventory is reported."
        }
    }

    private static func nextStep(for status: LocalSourceInspectionReport.Status) -> String {
        switch status {
        case .verifiedObservedBytes:
            return "Next: review the separate declaration assessment below before considering compatibility."
        case .unsupportedSelection:
            return "Next: review the selection limits in Documentation/LocalSourceInspection.md. Keep the original Podspec intact; removing declarations to obtain a successful report would change what is being inspected."
        case .unavailable:
            return "Next: check the explicit inputs against the reasons above and retry only when they are readable and stable."
        }
    }

    private static func explanation(for code: LocalSourceInspectionReport.Reason.Code) -> String {
        switch code {
        case .invalidInputPath:
            return "An explicit input path is invalid; use a path without traversal or control characters."
        case .invalidPodspec:
            return "The input is not a valid Podspec JSON document supported by this inspector. Ruby Podspecs are not executed."
        case .invalidSourcePath:
            return "A source entry is not a supported canonical relative path."
        case .missingInput:
            return "A required input could not be found. Check the supplied Podspec and source root."
        case .unreadableInput:
            return "An input could not be read. Check access to the supplied inputs."
        case .nonRegularFile:
            return "An input has the wrong file type; Podspec and source files must be regular files, and directory components must be directories."
        case .symbolicLink:
            return "An input or ancestor is a symbolic link. Supply a physical path; links are not followed."
        case .limitExceeded:
            return "An input or report exceeds an inspection size or count limit."
        case .changedDuringRead:
            return "An input changed during inspection. Retry against a stable source snapshot."
        case .missingSourceSelection:
            return "No source_files entries were found at the Podspec root. Sources inside subspecs do not count as a root selection."
        case .unsupportedGlob:
            return "A source_files entry contains a pattern. This version accepts literal Swift file paths only and does not expand glob patterns."
        case .unsupportedSourceType:
            return "A source_files entry is not a supported literal Swift source selection."
        case .ambiguousScope:
            return "Subspec or platform-scoped source selection requires semantics this root-only inspector does not implement."
        case .excludedSources:
            return "Source exclusions are declared. This inspector cannot apply exclude_files rules."
        case .unknownSelectionSemantics:
            return "Some declarations have unresolved selection semantics. See the separate declaration reasons; this report cannot identify their original field names safely."
        case .duplicateSourcePath:
            return "Source entries repeat or collide when compared without case. No inventory is accepted."
        }
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
