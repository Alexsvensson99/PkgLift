import Testing
import Foundation
@testable import PkgLiftCocoaPods
import PkgLiftCore

@Suite("PodfileLockParser Tests")
struct PodfileLockParserTests {
    @Test("Parse SimplePodfile.lock")
    func testParseSimplePodfileLock() throws {
        let parser = PodfileLockParser()
        let yaml = """
        PODS:
          - Alamofire (5.6.2)
          - Quick (5.0.1)
          - SwiftyJSON (5.0.1)
        DEPENDENCIES:
          - Alamofire (~> 5.6)
          - Quick
          - SwiftyJSON (~> 5.0)
        """
        
        let deps = try parser.parse(content: yaml)
        #expect(deps.count == 3)
        #expect(deps.contains(where: { $0.name == "Alamofire" && $0.version == "5.6.2" && $0.isDirect }))
    }
}
