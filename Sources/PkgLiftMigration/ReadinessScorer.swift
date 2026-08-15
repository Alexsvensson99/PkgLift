//
//  ReadinessScorer.swift
//  PkgLiftMigration
//

import Foundation

/// Calculates migration readiness score (0-100)
public struct ReadinessScorer: Sendable {
    public init() {}
    
    /// Calculate readiness score based on project analysis
    public func score(
        autoCount: Int,
        totalDirectCount: Int,
        blockedDirectCount: Int,
        hasPostInstallHook: Bool,
        hasPreInstallHook: Bool,
        hasScriptPhase: Bool,
        hasDynamicRuby: Bool,
        noProjectRisks: Bool
    ) -> Int {
        guard totalDirectCount > 0 else { return 0 }
        
        let base = Double(autoCount) / Double(totalDirectCount) * 70.0
        
        let blockedPenalty = min(blockedDirectCount * 10, 30)
        let postInstallPenalty = hasPostInstallHook ? 5 : 0
        let preInstallPenalty = hasPreInstallHook ? 5 : 0
        let scriptPhasePenalty = hasScriptPhase ? 5 : 0
        let dynamicRubyPenalty = hasDynamicRuby ? 5 : 0
        
        let bonus = noProjectRisks ? 10 : 0
        
        let total = Int(base) - blockedPenalty - postInstallPenalty - preInstallPenalty - scriptPhasePenalty - dynamicRubyPenalty + bonus
        
        return max(0, min(100, total))
    }
}
