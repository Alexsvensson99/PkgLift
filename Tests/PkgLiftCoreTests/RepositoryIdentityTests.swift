import XCTest
@testable import PkgLiftCore

final class RepositoryIdentityTests: XCTestCase {
    func testNormalizesSchemeHostGitSuffixAndTrailingSlash() {
        XCTAssertTrue(RepositoryIdentity.matches(
            "HTTPS://GitHub.com/Alamofire/Alamofire.git/",
            "https://github.com/Alamofire/Alamofire"
        ))
    }

    func testRepositoryPathCaseIsPreserved() {
        XCTAssertFalse(RepositoryIdentity.matches(
            "https://example.com/Owner/Repository",
            "https://example.com/owner/repository"
        ))
    }
}
