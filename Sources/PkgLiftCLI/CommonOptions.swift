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

    @Option(
        name: .long,
        help: "Explicit path to the Xcode project. Combine with --workspace to select one project from a multi-project workspace."
    )
    var project: String?

    @Option(
        name: .long,
        help: "Explicit path to the Xcode workspace. Relative paths are resolved beneath --path."
    )
    var workspace: String?
}
