//
//  RegistryCommand.swift
//  PkgLiftCLI
//

import ArgumentParser
import Foundation
import PkgLiftCore
import PkgLiftRegistry
import Yams

struct RegistryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "registry",
        abstract: "Manage the dependency registry.",
        subcommands: [ValidateCommand.self]
    )
}

struct ValidateCommand: AsyncParsableCommand {
    @OptionGroup var common: CommonOptions

    static let configuration = CommandConfiguration(commandName: "validate", abstract: "Validate all registry entries.")

    mutating func run() async throws {
        let discovery = try FileDiscovery().discover(in: common.path)
        let configuration: PkgLiftConfiguration
        if let configPath = discovery.configPath {
            configuration = try ConfigurationLoader().load(from: configPath)
        } else {
            configuration = .default
        }

        var registryPaths: [String] = []
        if let localOverride = discovery.localRegistryPath {
            registryPaths.append(localOverride)
        }

        let additionalPaths = configuration.registry?.additionalPaths ?? []
        registryPaths.append(
            contentsOf: additionalPaths.map { resolveRegistryPath($0, base: discovery.rootPath) }
        )

        var mappingByPath: [String: RegistryMapping] = [:]
        var validationErrors: [RegistryValidationError] = []

        let sourceRegistryPath = URL(fileURLWithPath: discovery.rootPath)
            .appendingPathComponent("Registry")
        var isSourceRegistryDirectory: ObjCBool = false
        let hasSourceRegistry = FileManager.default.fileExists(
            atPath: sourceRegistryPath.path,
            isDirectory: &isSourceRegistryDirectory
        ) && isSourceRegistryDirectory.boolValue
        if hasSourceRegistry {
            registryPaths.append(sourceRegistryPath.path)
        }

        for path in registryPaths {
            try collectMappings(
                from: path,
                into: &mappingByPath,
                validationErrors: &validationErrors
            )
        }

        if !hasSourceRegistry {
            let loader = RegistryLoader(useBundledRegistry: true)
            try await loader.load()
            for mapping in await loader.getMappings() {
                mappingByPath["bundled/\(mapping.pod.fullName).yml"] = mapping
            }
        }

        validationErrors += RegistryValidator().validateAll(mappingByPath)

        guard validationErrors.isEmpty else {
            print("Registry validation failed with \(validationErrors.count) error(s).")
            for error in validationErrors {
                print("- \(error)")
            }
            throw ValidateError.validationFailed
        }

        print("Registry validation passed for \(mappingByPath.count) mapping(s).")
    }
}

private func resolveRegistryPath(_ path: String, base: String) -> String {
    if path.hasPrefix("/") {
        return path
    }
    return URL(fileURLWithPath: base).appendingPathComponent(path).path
}

private func collectMappings(
    from path: String,
    into mappingByPath: inout [String: RegistryMapping],
    validationErrors: inout [RegistryValidationError]
) throws {
    let directoryURL = URL(fileURLWithPath: path)
    var isDirectory: ObjCBool = false

    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return
    }

    guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: nil) else {
        throw ValidateError.unreadableDirectory(path)
    }

    let decoder = YAMLDecoder()
    for case let itemURL as URL in enumerator {
        let ext = itemURL.pathExtension.lowercased()
        guard (ext == "yml" || ext == "yaml"), !itemURL.lastPathComponent.hasPrefix("_") else { continue }

        do {
            let string = try String(contentsOf: itemURL, encoding: .utf8)
            let mapping = try decoder.decode(RegistryMapping.self, from: string)
            mappingByPath[itemURL.path] = mapping
        } catch {
            validationErrors.append(
                RegistryValidationError(
                    filePath: itemURL.path,
                    fieldPath: "file",
                    message: error.localizedDescription
                )
            )
        }
    }
}

private enum ValidateError: LocalizedError {
    case unreadableDirectory(String)
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .unreadableDirectory(let path):
            return "Cannot read registry directory: \(path)."
        case .validationFailed:
            return "Registry validation failed."
        }
    }
}
