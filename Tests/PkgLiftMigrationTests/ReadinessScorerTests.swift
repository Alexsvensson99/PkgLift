//
//  ReadinessScorerTests.swift
//  PkgLiftMigrationTests
//

import XCTest
@testable import PkgLiftMigration

final class ReadinessScorerTests: XCTestCase {
    func testPerfectScore() {
        let scorer = ReadinessScorer()
        let score = scorer.score(autoCount: 10, totalDirectCount: 10, blockedDirectCount: 0, hasPostInstallHook: false, hasPreInstallHook: false, hasScriptPhase: false, hasDynamicRuby: false, noProjectRisks: true)
        XCTAssertEqual(score, 80) // 10/10 * 70 = 70. 70 + 10 = 80
    }
    
    func testZeroWhenNoDirectDeps() {
        let scorer = ReadinessScorer()
        let score = scorer.score(autoCount: 0, totalDirectCount: 0, blockedDirectCount: 0, hasPostInstallHook: false, hasPreInstallHook: false, hasScriptPhase: false, hasDynamicRuby: false, noProjectRisks: false)
        XCTAssertEqual(score, 0)
    }
}
