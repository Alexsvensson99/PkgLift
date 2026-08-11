// PkgLiftCocoaPods/PodfileParser.swift
// Static parser for Podfile.

import Foundation
import PkgLiftCore

/// Statically parses a Podfile without executing Ruby.
public struct PodfileParser: Sendable {
    public enum Error: Swift.Error {
        case fileReadFailed(URL)
    }

    public init() {}
    
    /// Parses a Podfile from file URL.
    public func parse(fileURL: URL) throws -> (features: PodfileFeatures, directDependencies: [CocoaPodDependency], targets: [String]) {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw Error.fileReadFailed(fileURL)
        }
        return parse(content: content)
    }
    
    /// Parses a Podfile from string content.
    public func parse(content: String) -> (features: PodfileFeatures, directDependencies: [CocoaPodDependency], targets: [String]) {
        var features = PodfileFeatures()
        var directDependencies: [CocoaPodDependency] = []
        var targets: [String] = []
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") { continue }
            
            if trimmed.contains("use_frameworks!") {
                features.useFrameworks = true
            }
            if trimmed.contains("use_modular_headers!") {
                features.useModularHeaders = true
            }
            if trimmed.contains("inherit! :search_paths") {
                features.hasInheritSearchPaths = true
            }
            if trimmed.contains("post_install") {
                features.hasPostInstallHook = true
            }
            if trimmed.contains("pre_install") {
                features.hasPreInstallHook = true
            }
            if trimmed.contains("script_phase") {
                features.hasScriptPhase = true
            }
            
            // Conservative detection for Ruby constructs whose control flow or
            // values this static parser cannot prove. Any such construct keeps
            // migration out of AUTO.
            let dynamicPrefixes = [
                "def ", "if ", "unless ", "case ", "for ", "while ", "until ",
                "class ", "module ", "begin", "plugin ", "install!",
            ]
            let hasUnknownBlock = trimmed.hasSuffix(" do")
                && !trimmed.hasPrefix("target ")
                && !trimmed.hasPrefix("abstract_target ")
                && !trimmed.hasPrefix("post_install ")
                && !trimmed.hasPrefix("pre_install ")
            let hasVariableAssignment = trimmed.range(
                of: #"^[a-zA-Z_]\w*\s*=(?!=)"#,
                options: .regularExpression
            ) != nil
            if dynamicPrefixes.contains(where: { trimmed.hasPrefix($0) })
                || hasUnknownBlock
                || hasVariableAssignment
                || trimmed.contains("require ")
                || trimmed.contains("#{")
                || trimmed.contains("eval(")
                || trimmed.contains("system(")
                || trimmed.contains("exec(")
                || trimmed.contains("%x{")
                || trimmed.contains("`") {
                features.hasDynamicRuby = true
            }
            
            if trimmed.hasPrefix("abstract_target") {
                features.hasAbstractTargets = true
            }
            
            // Extract pod declarations: pod 'Name' or pod "Name"
            if let match = trimmed.range(of: "^pod\\s+(['\"])(.*?)\\1", options: .regularExpression) {
                let podDeclaration = trimmed[match]
                let parts = podDeclaration.split(separator: " ", maxSplits: 1)
                if parts.count > 1 {
                    let name = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    let dep = CocoaPodDependency(name: name, version: nil, source: .registry, isDirect: true, targets: [])
                    directDependencies.append(dep)
                }
            }
            
            // Extract target declarations: target 'Name' do
            if let match = trimmed.range(of: "^target\\s+(['\"])(.*?)\\1\\s+do", options: .regularExpression) {
                let targetDeclaration = trimmed[match]
                if let nameMatch = targetDeclaration.range(of: "['\"](.*?)['\"]", options: .regularExpression) {
                    let name = String(targetDeclaration[nameMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    targets.append(name)
                }
            }
        }
        
        return (features, directDependencies, targets)
    }
}
