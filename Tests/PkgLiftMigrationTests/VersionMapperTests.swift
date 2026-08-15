//
//  VersionMapperTests.swift
//  PkgLiftMigrationTests
//

import XCTest
@testable import PkgLiftMigration

final class VersionMapperTests: XCTestCase {
    func testExactVersion() {
        let mapper = VersionMapper()
        XCTAssertEqual(mapper.map(constraint: "1.2.3"), .exact("1.2.3"))
        XCTAssertEqual(mapper.map(constraint: "= 1.2.3"), .exact("1.2.3"))
    }
    
    func testPessimisticOperator() {
        let mapper = VersionMapper()
        XCTAssertEqual(mapper.map(constraint: "~> 1.2"), .from("1.2.0"))
        XCTAssertEqual(mapper.map(constraint: "~> 1.2.3"), .upToNextMinor("1.2.3"))
    }
    
    func testGreaterThanOrEqual() {
        let mapper = VersionMapper()
        XCTAssertNil(mapper.map(constraint: ">= 1.0"))
        XCTAssertNil(mapper.map(constraint: ">= 1.2.3"))
    }
    
    func testComplexConstraintReturnsNil() {
        let mapper = VersionMapper()
        XCTAssertNil(mapper.map(constraint: ">= 1.0, < 2.0"))
    }
    
    func testEmptyConstraintUsesResolvedVersion() {
        let mapper = VersionMapper()
        XCTAssertEqual(mapper.map(constraint: "", resolvedVersion: "2.0.0"), .exact("2.0.0"))
    }

    func testNonSemanticFourComponentVersionIsRefused() {
        XCTAssertNil(VersionMapper().map(constraint: "1.2.3.4"))
    }
}
