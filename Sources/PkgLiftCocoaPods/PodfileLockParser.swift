// PkgLiftCocoaPods/PodfileLockParser.swift
// Parses Podfile.lock files.

import Foundation
import Yams
import PkgLiftCore

/// Parses Podfile.lock files without relying on Ruby.
public struct PodfileLockParser: Sendable {
    public enum Error: Swift.Error {
        case fileReadFailed(URL)
        case yamlParsingFailed
        case malformedStructure
    }
    
    public init() {}
    
    /// Parse Podfile.lock from file URL.
    public func parse(fileURL: URL) throws -> [CocoaPodDependency] {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw Error.fileReadFailed(fileURL)
        }
        return try parse(content: content)
    }
    
    /// Parse Podfile.lock from string content.
    public func parse(content: String) throws -> [CocoaPodDependency] {
        guard let yaml = try? Yams.load(yaml: content) as? [String: Any] else {
            throw Error.yamlParsingFailed
        }
        
        // Direct pods are listed in "DEPENDENCIES" array
        var directDependencies: Set<String> = []
        if let dependencies = yaml["DEPENDENCIES"] as? [String] {
            for dep in dependencies {
                let name = extractPodName(from: dep)
                directDependencies.insert(name)
            }
        }
        
        // External sources
        let externalSources = yaml["EXTERNAL SOURCES"] as? [String: [String: Any]] ?? [:]
        
        // Checkout options
        let checkoutOptions = yaml["CHECKOUT OPTIONS"] as? [String: [String: Any]] ?? [:]
        
        // CocoaPods emits a lockfile containing only its checksum and version
        // after the last dependency is removed. Accept that exact empty state,
        // but continue to reject a missing or malformed PODS section whenever
        // dependency declarations remain.
        let pods: [Any]
        if let rawPods = yaml["PODS"] {
            guard let parsedPods = rawPods as? [Any] else {
                throw Error.malformedStructure
            }
            pods = parsedPods
        } else {
            guard directDependencies.isEmpty, yaml["COCOAPODS"] != nil else {
                throw Error.malformedStructure
            }
            return []
        }

        // Parse PODS section
        var results: [CocoaPodDependency] = []
        
        for podEntry in pods {
            if let stringEntry = podEntry as? String {
                if let parsed = parsePodEntry(stringEntry, directDependencies: directDependencies, externalSources: externalSources, checkoutOptions: checkoutOptions) {
                    results.append(parsed)
                }
            } else if let dictEntry = podEntry as? [String: Any], let key = dictEntry.keys.first {
                if let parsed = parsePodEntry(key, directDependencies: directDependencies, externalSources: externalSources, checkoutOptions: checkoutOptions) {
                    results.append(parsed)
                }
            }
        }
        
        return results
    }
    
    private func extractPodName(from string: String) -> String {
        let parts = string.split(separator: " ", maxSplits: 1)
        return String(parts.first ?? "")
    }
    
    private func parsePodEntry(_ entry: String, directDependencies: Set<String>, externalSources: [String: [String: Any]], checkoutOptions: [String: [String: Any]]) -> CocoaPodDependency? {
        let nameAndVersion = entry.split(separator: " ", maxSplits: 1)
        guard let rawName = nameAndVersion.first else { return nil }
        
        let name = String(rawName)
        let baseName = extractBaseName(from: name)
        
        var version: String? = nil
        if nameAndVersion.count > 1 {
            let verString = nameAndVersion[1]
            if verString.hasPrefix("(") && verString.hasSuffix(")") {
                version = String(verString.dropFirst().dropLast())
            }
        }
        
        // CocoaPods lists the exact declarations from the Podfile under
        // DEPENDENCIES. A base pod declaration must not make each of its
        // transitive subspecs look direct and therefore removable.
        let isDirect = directDependencies.contains(name)
        
        var source: PodSource = .registry
        
        if let ext = externalSources[baseName] {
            if let path = ext[":path"] as? String {
                source = .path(path)
            } else if let git = ext[":git"] as? String {
                var ref: GitRef? = nil
                let checkout = checkoutOptions[baseName] ?? ext
                
                if let branch = checkout[":branch"] as? String ?? ext[":branch"] as? String {
                    ref = .branch(branch)
                } else if let tag = checkout[":tag"] as? String ?? ext[":tag"] as? String {
                    ref = .tag(tag)
                } else if let commit = checkout[":commit"] as? String ?? ext[":commit"] as? String {
                    ref = .commit(commit)
                }
                
                source = .git(url: git, ref: ref)
            }
        }
        
        return CocoaPodDependency(name: name, version: version, source: source, isDirect: isDirect, targets: [])
    }
    
    private func extractBaseName(from name: String) -> String {
        if let slashIndex = name.firstIndex(of: "/") {
            return String(name[name.startIndex..<slashIndex])
        }
        return name
    }
}
