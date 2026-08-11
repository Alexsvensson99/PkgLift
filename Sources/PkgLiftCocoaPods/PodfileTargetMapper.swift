// PkgLiftCocoaPods/PodfileTargetMapper.swift
// Maps dependencies to targets based on Podfile blocks.

import Foundation
import PkgLiftCore

/// Maps CocoaPods dependencies to Xcode targets based on Podfile structure.
public struct PodfileTargetMapper: Sendable {
    public init() {}
    
    /// Associates parsed dependencies with targets based on their nesting in the Podfile.
    public func map(podfileContent: String, lockfileDependencies: [CocoaPodDependency]) -> [CocoaPodDependency] {
        var targetMapping: [String: Set<String>] = [:] // pod base name -> set of targets
        var currentTargets: [String] = []
        
        let lines = podfileContent.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") { continue }
            
            if let match = trimmed.range(of: "^target\\s+(['\"])(.*?)\\1\\s+do", options: .regularExpression) {
                let targetDeclaration = trimmed[match]
                if let nameMatch = targetDeclaration.range(of: "['\"](.*?)['\"]", options: .regularExpression) {
                    let name = String(targetDeclaration[nameMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    currentTargets.append(name)
                }
            } else if trimmed.hasPrefix("end") {
                if !currentTargets.isEmpty {
                    currentTargets.removeLast()
                }
            } else if let match = trimmed.range(of: "^pod\\s+(['\"])(.*?)\\1", options: .regularExpression) {
                let podDeclaration = trimmed[match]
                let parts = podDeclaration.split(separator: " ", maxSplits: 1)
                if parts.count > 1 {
                    let name = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    
                    let baseName: String
                    if let slashIndex = name.firstIndex(of: "/") {
                        baseName = String(name[name.startIndex..<slashIndex])
                    } else {
                        baseName = name
                    }
                    
                    if let target = currentTargets.last {
                        targetMapping[baseName, default: []].insert(target)
                        targetMapping[name, default: []].insert(target)
                    }
                }
            }
        }
        
        var mappedDependencies: [CocoaPodDependency] = []
        
        for dep in lockfileDependencies {
            var assignedTargets = Array(targetMapping[dep.name] ?? [])
            if assignedTargets.isEmpty {
                assignedTargets = Array(targetMapping[dep.baseName] ?? [])
            }
            
            let mapped = CocoaPodDependency(
                name: dep.name,
                version: dep.version,
                source: dep.source,
                isDirect: dep.isDirect,
                targets: assignedTargets.sorted()
            )
            mappedDependencies.append(mapped)
        }
        
        return mappedDependencies
    }
}
