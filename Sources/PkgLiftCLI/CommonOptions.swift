//
//  CommonOptions.swift
//  PkgLiftCLI
//

import ArgumentParser
import Foundation

struct CommonOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "The path to the project directory.")
    var path: String = FileManager.default.currentDirectoryPath

    @Flag(name: .long, help: "Output results in JSON format.")
    var json: Bool = false

    @Flag(name: .long, help: "Disable colored output.")
    var noColor: Bool = false

    @Option(name: .long, help: "Explicit path to the Xcode project.")
    var project: String?

    @Option(name: .long, help: "Explicit path to the Xcode workspace.")
    var workspace: String?
}
