// PkgLiftCocoaPods/PodfileTargetMapper.swift
// Maps dependencies to targets based on Podfile blocks.

import Foundation
import PkgLiftCore

/// Maps CocoaPods dependencies to Xcode targets based on Podfile structure.
public struct PodfileTargetMapper: Sendable {
    private enum Block {
        case target(String)
        case other
    }

    public init() {}

    /// Associates parsed dependencies with targets based on their nesting in the Podfile.
    public func map(podfileContent: String, lockfileDependencies: [CocoaPodDependency]) -> [CocoaPodDependency] {
        var targetMapping: [String: Set<String>] = [:]
        var blocks: [Block] = []

        let lines = podfileContent.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") { continue }

            if PodfileStaticSyntax.isTargetDeclaration(trimmed) {
                if let targetName = PodfileStaticSyntax.targetName(from: trimmed) {
                    blocks.append(.target(targetName))
                } else {
                    // Preserve block balance but do not infer a computed target.
                    blocks.append(.other)
                }
                continue
            }

            if PodfileStaticSyntax.closesBlock(trimmed) {
                if !blocks.isEmpty {
                    blocks.removeLast()
                }
                continue
            }

            if let podName = PodfileStaticSyntax.podName(from: trimmed),
               let target = blocks.reversed().compactMap({ block -> String? in
                   guard case .target(let name) = block else { return nil }
                   return name
               }).first {
                let baseName: String
                if let slashIndex = podName.firstIndex(of: "/") {
                    baseName = String(podName[podName.startIndex..<slashIndex])
                } else {
                    baseName = podName
                }

                targetMapping[baseName, default: []].insert(target)
                targetMapping[podName, default: []].insert(target)
                continue
            }

            if PodfileStaticSyntax.opensNonTargetBlock(trimmed) {
                blocks.append(.other)
            }
        }

        return lockfileDependencies.map { dependency in
            var assignedTargets = Array(targetMapping[dependency.name] ?? [])
            if assignedTargets.isEmpty {
                assignedTargets = Array(targetMapping[dependency.baseName] ?? [])
            }

            return CocoaPodDependency(
                name: dependency.name,
                version: dependency.version,
                source: dependency.source,
                isDirect: dependency.isDirect,
                targets: assignedTargets.sorted()
            )
        }
    }
}
