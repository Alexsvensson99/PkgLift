import Testing
import Foundation
@testable import PkgLiftCocoaPods
import PkgLiftCore

@Suite("PodfileTargetMapper Tests")
struct PodfileTargetMapperTests {
    @Test("Map Dependencies to Targets")
    func testMapDependencies() throws {
        let mapper = PodfileTargetMapper()
        let content = """
        target 'MyApp' do
          pod 'Alamofire'
        end
        """
        let deps = [CocoaPodDependency(name: "Alamofire", version: "5.0.0", source: .registry, isDirect: true, targets: [])]
        
        let mapped = mapper.map(podfileContent: content, lockfileDependencies: deps)
        #expect(mapped.count == 1)
        #expect(mapped.first?.targets == ["MyApp"])
    }
}
