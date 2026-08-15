import ArgumentParser
import Foundation
import PkgLiftCore
import PkgLiftMigration

struct DiagnosticsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diagnostics",
        abstract: "Write a local, privacy-preserving diagnostics report."
    )

    @OptionGroup var common: CommonOptions

    @Option(
        name: .long,
        help: "Output JSON file. Relative paths are resolved from the current working directory."
    )
    var output: String

    @Flag(name: .long, help: "Replace an existing regular output file.")
    var overwrite: Bool = false

    mutating func run() async throws {
        let outputURL = try Self.resolveOutputURL(output)
        let environment = DiagnosticsEnvironmentCollector().collect()

        var failures: [DiagnosticsFailure] = []
        var discovery: DiscoveredFiles?
        var analysis: ProjectAnalysis?
        var git = DiagnosticsGitSummary.unknown

        do {
            discovery = try FileDiscovery().discover(in: common.path)
        } catch {
            failures.append(DiagnosticsFailure(stage: .discovery, error: error))
        }

        if let discovery {
            do {
                let result = try GitSafetyChecker().check(
                    directory: URL(fileURLWithPath: discovery.rootPath, isDirectory: true)
                )
                if !result.isRepository {
                    git = DiagnosticsGitSummary(state: .notRepository, changedFileCount: 0)
                } else if result.isClean {
                    git = DiagnosticsGitSummary(state: .clean, changedFileCount: 0)
                } else {
                    git = DiagnosticsGitSummary(
                        state: .dirty,
                        changedFileCount: result.changedFiles.count
                    )
                }
            } catch {
                failures.append(DiagnosticsFailure(stage: .git, error: error))
            }

            do {
                let context = try await CommandContext.load(from: common)
                analysis = context.buildProjectAnalysis()
            } catch {
                failures.append(DiagnosticsFailure(stage: .analysis, error: error))
            }
        }

        let report = DiagnosticsReportBuilder().build(
            environment: environment,
            discovery: discovery,
            analysis: analysis,
            git: git,
            failures: failures
        )

        try DiagnosticsReportWriter().write(
            report,
            to: outputURL,
            overwrite: overwrite
        )

        let printer = DiagnosticPrinter(
            color: ColorSupport(forceDisable: common.noColor)
        )
        if report.status == .partial {
            printer.warning(
                "Diagnostics report is partial.",
                detail: "One or more stages could not be inspected; see the typed failures array."
            )
        }
        printer.success("Diagnostics report written to \(outputURL.path)")
        printer.info("Review the JSON before sharing it. PkgLift never uploads the report automatically.")
    }

    static func resolveOutputURL(
        _ value: String,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) throws -> URL {
        if value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            throw DiagnosticsCommandError.invalidOutputPath
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw DiagnosticsCommandError.invalidOutputPath
        }

        if (normalized as NSString).isAbsolutePath {
            return URL(fileURLWithPath: normalized, isDirectory: false)
                .standardizedFileURL
        }

        return URL(fileURLWithPath: currentDirectory, isDirectory: true)
            .standardizedFileURL
            .appendingPathComponent(normalized, isDirectory: false)
            .standardizedFileURL
    }
}

private struct DiagnosticsEnvironmentCollector: Sendable {
    private let processRunner = ProcessRunner()

    func collect() -> DiagnosticsEnvironmentSummary {
        DiagnosticsEnvironmentSummary(
            macOS: Self.normalizedVersion(ProcessInfo.processInfo.operatingSystemVersionString),
            xcode: capture(executable: "xcodebuild", arguments: ["-version"], maximumLines: 2),
            swift: capture(executable: "swift", arguments: ["--version"], maximumLines: 2),
            cocoaPods: capture(executable: "pod", arguments: ["--version"], maximumLines: 1)
        )
    }

    private func capture(
        executable: String,
        arguments: [String],
        maximumLines: Int
    ) -> String? {
        guard let executablePath = processRunner.findExecutable(executable),
              let result = try? processRunner.run(
                executable: executablePath,
                arguments: arguments
              ),
              result.succeeded else {
            return nil
        }

        let source = result.stdout.isEmpty ? result.stderr : result.stdout
        let lines = source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maximumLines)
        guard !lines.isEmpty else { return nil }
        return Self.normalizedVersion(lines.joined(separator: " | "))
    }

    private static func normalizedVersion(_ value: String) -> String {
        let allowed = value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }
        return String(String.UnicodeScalarView(allowed)).trimmingCharacters(in: .whitespaces)
    }
}

private enum DiagnosticsCommandError: LocalizedError {
    case invalidOutputPath

    var errorDescription: String? {
        switch self {
        case .invalidOutputPath:
            return "Diagnostics --output must be a non-empty path without control characters."
        }
    }
}
