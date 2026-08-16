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

    @Test("Only exact lockfile declarations are direct")
    func testExactDirectDependencyIdentity() throws {
        let yaml = """
        PODS:
          - SDWebImage (5.18.1):
            - SDWebImage/Core (= 5.18.1)
          - SDWebImage/Core (5.18.1)
          - Firebase/Analytics (8.0.0)
        DEPENDENCIES:
          - SDWebImage
          - Firebase/Analytics
        """

        let dependencies = try PodfileLockParser().parse(content: yaml)
        #expect(dependencies.first(where: { $0.name == "SDWebImage" })?.isDirect == true)
        #expect(dependencies.first(where: { $0.name == "SDWebImage/Core" })?.isDirect == false)
        #expect(dependencies.first(where: { $0.name == "Firebase/Analytics" })?.isDirect == true)
    }

    @Test("Accept CocoaPods lockfile after the last dependency is removed")
    func testEmptyCocoaPodsLockfile() throws {
        let yaml = """
        PODFILE CHECKSUM: 1f9e936cbada7b57cc466bea376ead75c3eb263f

        COCOAPODS: 1.16.2
        """

        #expect(try PodfileLockParser().parse(content: yaml).isEmpty)
    }

    @Test("Reject dependencies without a PODS section")
    func testMissingPodsSectionWithDependenciesIsMalformed() {
        let yaml = """
        DEPENDENCIES:
          - SDWebImage (= 5.18.1)
        COCOAPODS: 1.16.2
        """

        #expect(throws: PodfileLockParser.Error.self) {
            try PodfileLockParser().parse(content: yaml)
        }
    }
}
