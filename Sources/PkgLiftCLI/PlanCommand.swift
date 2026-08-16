//
//  PlanCommand.swift
//  PkgLiftCLI
//

import ArgumentParser
import Foundation
import PkgLiftCore

struct PlanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "plan", abstract: "Generate a migration plan.")

    @OptionGroup var common: CommonOptions

    @Flag(
        name: .customLong("portable-json"),
        help: "Output a shareable redacted copy while retaining the full saved plan."
    )
    var portableJSON: Bool = false

    mutating func validate() throws {
        if common.json && portableJSON {
            throw ValidationError("--json and --portable-json are mutually exclusive.")
        }
    }

    mutating func run() async throws {
        let context = try await CommandContext.load(from: common)
        let plan = context.buildMigrationPlan()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(plan)

        let directory = context.planURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: context.planURL, options: .atomic)

        if common.json || portableJSON {
            let output = try PortableJSON().output(from: data, portable: portableJSON)
            guard let json = String(data: output, encoding: .utf8) else {
                throw PlanError.encodingFailed
            }
            print(json)
            return
        }

        print("Plan generated: \(context.planURL.path)")
        print("AUTO: \(plan.autoEntries.count)")
        print("REVIEW: \(plan.reviewEntries.count)")
        print("BLOCKED: \(plan.blockedEntries.count)")
        print("UNKNOWN: \(plan.unknownEntries.count)")
    }
}

private enum PlanError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode migration plan as JSON."
        }
    }
}
