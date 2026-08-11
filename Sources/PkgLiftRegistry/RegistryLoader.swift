import Foundation
import PkgLiftCore
import Yams

/// Loads and manages registry mappings.
public actor RegistryLoader {
    /// Ordered list of paths to load from. Highest precedence first.
    private let configPaths: [URL]
    private let localOverridePath: URL?
    private let useBundledRegistry: Bool
    
    private var mappings: [RegistryMapping] = []
    
    /// Initializes a registry loader.
    /// - Parameters:
    ///   - configPaths: Additional paths specified in config.
    ///   - localOverridePath: Path to `.pkglift/registry/` or similar.
    ///   - useBundledRegistry: Whether to load the bundled registry.
    public init(configPaths: [URL] = [], localOverridePath: URL? = nil, useBundledRegistry: Bool = true) {
        self.configPaths = configPaths
        self.localOverridePath = localOverridePath
        self.useBundledRegistry = useBundledRegistry
    }
    
    /// Loads all registry mappings.
    /// - Throws: `RegistryError` if parsing fails and cannot be recovered.
    public func load() throws {
        var allMappings: [RegistryMapping] = []
        var loadedNames: Set<String> = []
        
        // 1. Local Overrides
        if let localPath = localOverridePath {
            try loadDirectory(at: localPath, into: &allMappings, loadedNames: &loadedNames)
        }
        
        // 2. Config Paths
        for path in configPaths {
            try loadDirectory(at: path, into: &allMappings, loadedNames: &loadedNames)
        }
        
        // 3. Bundled Registry
        if useBundledRegistry {
            let candidates = BundledRegistryLocator.candidateURLs()
            guard let bundledPath = BundledRegistryLocator.locate(in: candidates) else {
                throw RegistryError.bundledRegistryNotFound(candidates.map(\.path))
            }
            try loadDirectory(at: bundledPath, into: &allMappings, loadedNames: &loadedNames)
        }
        
        self.mappings = allMappings
    }
    
    /// Returns the currently loaded mappings.
    public func getMappings() -> [RegistryMapping] {
        return mappings
    }
    
    /// Looks up a mapping by pod name and optional subspec.
    /// - Parameters:
    ///   - name: The pod name.
    ///   - subspec: The optional subspec.
    /// - Returns: The matching `RegistryMapping`, if found.
    public func lookup(name: String, subspec: String? = nil) -> RegistryMapping? {
        let identifier = PodIdentifier(name: name, subspec: subspec)
        
        // First try an exact match (name + subspec)
        if let exact = mappings.first(where: { $0.pod == identifier }) {
            return exact
        }
        
        // If subspec is provided but no exact match, try matching just the main pod
        if subspec != nil {
            if let main = mappings.first(where: { $0.pod.name == name && $0.pod.subspec == nil }) {
                return main
            }
        }
        
        return nil
    }
    
    private func loadDirectory(at url: URL, into mappings: inout [RegistryMapping], loadedNames: inout Set<String>) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else {
            throw RegistryError.unreadableDirectory(url.path)
        }
        
        var identifiersInDirectory: [String: String] = [:]
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "yml" || fileURL.pathExtension.lowercased() == "yaml" else {
                continue
            }
            guard !fileURL.lastPathComponent.hasPrefix("_") else { continue }
            
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = YAMLDecoder()
                let mapping = try decoder.decode(RegistryMapping.self, from: data)
                let validationErrors = RegistryValidator().validate(mapping, filePath: fileURL.path)
                if !validationErrors.isEmpty {
                    throw RegistryError.validationFailed(validationErrors)
                }
                
                let fullName = mapping.pod.fullName
                if let firstPath = identifiersInDirectory[fullName] {
                    throw RegistryError.validationFailed([
                        RegistryValidationError(
                            filePath: fileURL.path,
                            fieldPath: "pod",
                            message: "Duplicate mapping for '\(fullName)' in the same registry source. Also defined in \(firstPath)."
                        )
                    ])
                }
                identifiersInDirectory[fullName] = fileURL.path
                if !loadedNames.contains(fullName) {
                    mappings.append(mapping)
                    loadedNames.insert(fullName)
                }
            } catch let error as RegistryError {
                throw error
            } catch {
                throw RegistryError.parsingError(path: fileURL.path, message: error.localizedDescription)
            }
        }
    }
}

enum BundledRegistryLocator {
    private static let bundleName = "PkgLift_PkgLiftRegistry.bundle"
    private static let registryName = "BundledRegistry"

    static func candidateURLs(
        mainBundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL,
        containingBundleURL: URL = Bundle(for: RegistryBundleToken.self).bundleURL
    ) -> [URL] {
        var directories = [mainBundleURL]
        if let executableURL {
            directories.append(
                executableURL
                    .resolvingSymlinksInPath()
                    .deletingLastPathComponent()
            )
        }
        directories.append(containingBundleURL)
        directories.append(containingBundleURL.deletingLastPathComponent())

        var seenPaths: Set<String> = []
        return directories.compactMap { directory in
            let candidate = directory
                .appendingPathComponent(bundleName, isDirectory: true)
                .appendingPathComponent(registryName, isDirectory: true)
                .standardizedFileURL
            guard seenPaths.insert(candidate.path).inserted else { return nil }
            return candidate
        }
    }

    static func locate(in candidates: [URL]) -> URL? {
        let fileManager = FileManager.default
        return candidates.first { candidate in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }
}

private final class RegistryBundleToken {}
