//
//  VersionCommand.swift
//  PkgLiftCLI
//

import ArgumentParser

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "version", abstract: "Print version number.")

    mutating func run() throws {
        print(pkgLiftVersion)
    }
}
