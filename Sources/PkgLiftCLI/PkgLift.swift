//
//  PkgLift.swift
//  PkgLiftCLI
//

import ArgumentParser

let pkgLiftVersion = "0.1.0"

@main
struct PkgLift: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pkglift",
        abstract: "Modernize Apple dependencies safely.",
        version: pkgLiftVersion,
        subcommands: [AnalyzeCommand.self, PlanCommand.self, MigrateCommand.self, VerifyCommand.self, RegistryCommand.self, VersionCommand.self]
    )
}
