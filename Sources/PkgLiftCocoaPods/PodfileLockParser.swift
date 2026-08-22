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
        let rootNode: Node
        do {
            guard let composed = try Yams.compose(yaml: content) else {
                throw Error.yamlParsingFailed
            }
            rootNode = composed
        } catch {
            throw Error.yamlParsingFailed
        }
        try validateExternalSourceNodes(in: rootNode)

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
        
        // External source data crosses the same untrusted boundary as the
        // Podfile. Validate its shape before any value can reach a model or JSON
        // artifact, then retain only canonical repository and bounded ref data.
        let externalSources = try mappingSection(named: "EXTERNAL SOURCES", in: yaml)
        let checkoutOptions = try mappingSection(named: "CHECKOUT OPTIONS", in: yaml)
        
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
    
    private func parsePodEntry(
        _ entry: String,
        directDependencies: Set<String>,
        externalSources: [String: [String: Any]],
        checkoutOptions: [String: [String: Any]]
    ) -> CocoaPodDependency? {
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
        
        let parsedSource = parsedSource(
            external: externalSources[baseName],
            checkout: checkoutOptions[baseName]
        )

        return CocoaPodDependency(
            name: name,
            version: version,
            source: parsedSource.source,
            sourceProvenance: parsedSource.provenance,
            isDirect: isDirect,
            targets: []
        )
    }
    
    private func extractBaseName(from name: String) -> String {
        if let slashIndex = name.firstIndex(of: "/") {
            return String(name[name.startIndex..<slashIndex])
        }
        return name
    }

    private func mappingSection(
        named name: String,
        in yaml: [String: Any]
    ) throws -> [String: [String: Any]] {
        guard let rawSection = yaml[name] else { return [:] }
        guard let section = rawSection as? [String: Any] else {
            throw Error.malformedStructure
        }

        var result: [String: [String: Any]] = [:]
        for (dependency, rawOptions) in section {
            guard let options = rawOptions as? [String: Any] else {
                throw Error.malformedStructure
            }
            result[dependency] = options
        }
        return result
    }

    private func parsedSource(
        external: [String: Any]?,
        checkout: [String: Any]?
    ) -> ParsedLockfileSource {
        guard external != nil || checkout != nil else {
            return ParsedLockfileSource(source: .registry)
        }

        let path = stringValue(for: ":path", in: external)
        let externalGit = repositoryValue(for: ":git", in: external)
        let checkoutGit = repositoryValue(for: ":git", in: checkout)
        let hasGitEvidence = external?.keys.contains(":git") == true
            || checkout?.keys.contains(":git") == true

        guard hasGitEvidence else {
            if let value = path.value, !path.isMalformed {
                return ParsedLockfileSource(source: .path(value))
            }
            return ParsedLockfileSource(source: .unknown)
        }

        let externalReference = externalReference(in: external)
        let checkoutDeclaredReference = checkoutDeclaredReference(in: checkout)
        let checkoutCommit = referenceValue(kind: .commit, key: ":commit", in: checkout)
        let hasPathConflict = external?.keys.contains(":path") == true
        let hasUnsupportedExternalOption = containsUnsupportedKeys(
            in: external,
            allowed: [":git", ":path", ":branch", ":tag", ":commit"]
        )
        let hasUnsupportedCheckoutOption = containsUnsupportedKeys(
            in: checkout,
            allowed: [":git", ":branch", ":tag", ":commit"]
        )
        let lockfile = GitLockfileEvidence(
            externalSourceRepository: externalGit.evidence,
            externalSourceReference: externalReference.reference,
            checkoutRepository: checkoutGit.evidence,
            checkoutDeclaredReference: checkoutDeclaredReference.reference,
            checkoutReference: checkoutCommit.reference,
            hasConflictingEvidence: hasPathConflict
                || externalReference.isConflicting
                || checkoutDeclaredReference.isConflicting,
            hasMalformedEvidence: path.isMalformed
                || externalGit.isMalformed
                || checkoutGit.isMalformed
                || externalReference.isMalformed
                || checkoutDeclaredReference.isMalformed
                || checkoutCommit.isMalformed
                || hasUnsupportedExternalOption
                || hasUnsupportedCheckoutOption
        )
        let provenance = GitSourceProvenance(declarations: [], lockfile: lockfile)
        let displayRepository = externalGit.evidence ?? checkoutGit.evidence
        let source: PodSource
        if hasPathConflict {
            source = .unknown
        } else if let displayRepository {
            source = .git(
                url: displayRepository.displayURL,
                ref: legacyGitReference(from: externalReference.reference)
            )
        } else {
            source = .unknown
        }
        return ParsedLockfileSource(source: source, provenance: .git(provenance))
    }

    private func externalReference(in options: [String: Any]?) -> ParsedReference {
        let candidates: [(GitReferenceKind, String)] = [
            (.branch, ":branch"),
            (.tag, ":tag"),
            (.commit, ":commit"),
        ].filter { options?.keys.contains($0.1) == true }

        guard !candidates.isEmpty else {
            return ParsedReference(reference: .unpinned)
        }
        guard candidates.count == 1, let candidate = candidates.first else {
            return ParsedReference(isConflicting: true)
        }
        return referenceValue(kind: candidate.0, key: candidate.1, in: options)
    }

    private func checkoutDeclaredReference(in options: [String: Any]?) -> ParsedReference {
        let candidates: [(GitReferenceKind, String)] = [
            (.branch, ":branch"),
            (.tag, ":tag"),
        ].filter { options?.keys.contains($0.1) == true }

        guard !candidates.isEmpty else { return ParsedReference() }
        guard candidates.count == 1, let candidate = candidates.first else {
            return ParsedReference(isConflicting: true)
        }
        return referenceValue(kind: candidate.0, key: candidate.1, in: options)
    }

    private func referenceValue(
        kind: GitReferenceKind,
        key: String,
        in options: [String: Any]?
    ) -> ParsedReference {
        guard let rawValue = options?[key] else { return ParsedReference() }
        guard let value = rawValue as? String,
              let reference = GitReferenceEvidence.make(kind: kind, value: value) else {
            return ParsedReference(isMalformed: true)
        }
        return ParsedReference(reference: reference)
    }

    private func repositoryValue(
        for key: String,
        in options: [String: Any]?
    ) -> ParsedRepository {
        guard let rawValue = options?[key] else { return ParsedRepository() }
        guard let value = rawValue as? String else {
            return ParsedRepository(
                evidence: GitRepositoryCanonicalizer.evidence(
                    for: GitRepositoryEvidence.redactedDisplayURL
                ),
                isMalformed: true
            )
        }
        return ParsedRepository(evidence: GitRepositoryCanonicalizer.evidence(for: value))
    }

    private func stringValue(for key: String, in options: [String: Any]?) -> ParsedString {
        guard let rawValue = options?[key] else { return ParsedString() }
        guard let value = rawValue as? String else {
            return ParsedString(isMalformed: true)
        }
        return ParsedString(value: value)
    }

    private func legacyGitReference(from evidence: GitReferenceEvidence?) -> GitRef? {
        guard let evidence, let value = evidence.value else { return nil }
        switch evidence.kind {
        case .branch:
            return .branch(value)
        case .tag:
            return .tag(value)
        case .commit:
            return .commit(value)
        case .unpinned:
            return nil
        }
    }

    private func containsUnsupportedKeys(
        in options: [String: Any]?,
        allowed: Set<String>
    ) -> Bool {
        guard let options else { return false }
        return !Set(options.keys).isSubset(of: allowed)
    }

    /// Dictionary decoding keeps only one value for a repeated YAML key. Check
    /// the node sequence first so duplicate source/ref evidence cannot silently
    /// become last-value-wins input.
    private func validateExternalSourceNodes(in root: Node) throws {
        guard let rootMapping = root.mapping else {
            throw Error.malformedStructure
        }

        for sectionName in ["EXTERNAL SOURCES", "CHECKOUT OPTIONS"] {
            let sections = rootMapping.filter { $0.key.string == sectionName }
            guard sections.count <= 1 else {
                throw Error.malformedStructure
            }
            guard let section = sections.first else { continue }
            guard let dependencies = section.value.mapping else {
                throw Error.malformedStructure
            }

            var dependencyNames: Set<String> = []
            for pair in dependencies {
                guard let dependencyName = pair.key.string,
                      dependencyNames.insert(dependencyName).inserted,
                      let options = pair.value.mapping else {
                    throw Error.malformedStructure
                }

                var optionNames: Set<String> = []
                for option in options {
                    guard let optionName = option.key.string,
                          optionNames.insert(optionName).inserted else {
                        throw Error.malformedStructure
                    }
                }
            }
        }
    }
}

private struct ParsedLockfileSource {
    let source: PodSource
    let provenance: DependencySourceProvenance?

    init(source: PodSource, provenance: DependencySourceProvenance? = nil) {
        self.source = source
        self.provenance = provenance
    }
}

private struct ParsedRepository {
    let evidence: GitRepositoryEvidence?
    let isMalformed: Bool

    init(evidence: GitRepositoryEvidence? = nil, isMalformed: Bool = false) {
        self.evidence = evidence
        self.isMalformed = isMalformed
    }
}

private struct ParsedReference {
    let reference: GitReferenceEvidence?
    let isConflicting: Bool
    let isMalformed: Bool

    init(
        reference: GitReferenceEvidence? = nil,
        isConflicting: Bool = false,
        isMalformed: Bool = false
    ) {
        self.reference = reference
        self.isConflicting = isConflicting
        self.isMalformed = isMalformed
    }
}

private struct ParsedString {
    let value: String?
    let isMalformed: Bool

    init(value: String? = nil, isMalformed: Bool = false) {
        self.value = value
        self.isMalformed = isMalformed
    }
}
