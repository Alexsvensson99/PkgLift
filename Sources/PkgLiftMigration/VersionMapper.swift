// PkgLiftMigration/VersionMapper.swift
// Converts CocoaPods version constraints to SwiftPM.

import Foundation
import PkgLiftCore
import PkgLiftCocoaPods

/// Converts CocoaPods version constraints to SwiftPM.
public struct VersionMapper: Sendable {
    public enum SPMVersionConstraint: Equatable, Sendable {
        case exact(String)
        case from(String)
        case upToNextMinor(String)
    }

    public init() {}

    /// Map a CocoaPods constraint to SwiftPM.
    /// Returns nil if it's too complex.
    public func map(constraint: String, resolvedVersion: String? = nil) -> SPMVersionConstraint? {
        let trimmed = constraint.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            if let resolved = resolvedVersion, let normalized = normalize(resolved) {
                return .exact(normalized)
            }
            return nil
        }

        // Return nil immediately if it contains multiple constraints
        if trimmed.contains(",") {
            return nil
        }

        // Exact version e.g. "1.2.3", "= 1.2.3"
        guard let exactRegex = try? NSRegularExpression(pattern: #"^(?:=\s*)?(\d+(?:\.\d+)*)$"#) else {
            return nil
        }
        
        if let match = exactRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            let versionRange = match.range(at: 1)
            if let swiftRange = Range(versionRange, in: trimmed) {
                let versionStr = String(trimmed[swiftRange])
                if let normalized = normalize(versionStr) {
                    return .exact(normalized)
                }
            }
        }

        // CocoaPods' pessimistic operator advances the last specified
        // component except the patch component. Preserve that upper bound.
        if trimmed.hasPrefix("~>") {
            let versionStr = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let componentCount = versionStr.split(separator: ".").count
            if let normalized = normalize(versionStr) {
                return componentCount >= 3 ? .upToNextMinor(normalized) : .from(normalized)
            }
            return nil
        }

        // SwiftPM/Xcode has no open-ended lower-bound requirement. Mapping
        // this to `upToNextMajor` would silently change CocoaPods semantics.
        if trimmed.hasPrefix(">=") {
            return nil
        }

        return nil
    }

    // MARK: - Private Helpers

    private func normalize(_ version: String) -> String? {
        let clean = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = clean.split(separator: ".").map(String.init)
        guard !components.isEmpty, components.count <= 3 else { return nil }
        
        // Ensure all components are numeric
        for comp in components {
            guard Int(comp) != nil else { return nil }
        }
        
        if components.count == 1 {
            return "\(components[0]).0.0"
        } else if components.count == 2 {
            return "\(components[0]).\(components[1]).0"
        } else {
            return components.joined(separator: ".")
        }
    }
}
