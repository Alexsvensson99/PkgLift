//
//  PkgLift.swift
//  PkgLiftCLI
//

import ArgumentParser
import PkgLiftCore

@main
struct PkgLift: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pkglift",
        abstract: "Modernize Apple dependencies safely.",
        version: PkgLiftCore.pkgLiftVersion,
        subcommands: [AnalyzeCommand.self, PlanCommand.self, MigrateCommand.self, VerifyCommand.self, RegistryCommand.self, VersionCommand.self]
    )
}
