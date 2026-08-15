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
        let dependencies = [
            CocoaPodDependency(
                name: "Alamofire",
                version: "5.0.0",
                source: .registry,
                isDirect: true,
                targets: []
            )
        ]

        let mapped = mapper.map(podfileContent: content, lockfileDependencies: dependencies)
        #expect(mapped.count == 1)
        #expect(mapped.first?.targets == ["MyApp"])
    }

    @Test("Map literal target forms and preserve nested block scope")
    func testMapLiteralTargetFormsAndNestedBlocks() {
        let content = #"""
        target :Outer do
          if feature_enabled
            pod 'Alamofire'
          end

          target "Inner" do
            pod 'SnapKit'
          end

          pod 'Kingfisher'
        end
        """#
        let dependencies = [
            CocoaPodDependency(name: "Alamofire", version: "5.9.1", source: .registry, isDirect: true, targets: []),
            CocoaPodDependency(name: "SnapKit", version: "5.7.1", source: .registry, isDirect: true, targets: []),
            CocoaPodDependency(name: "Kingfisher", version: "8.0.0", source: .registry, isDirect: true, targets: []),
        ]

        let mapped = PodfileTargetMapper().map(
            podfileContent: content,
            lockfileDependencies: dependencies
        )
        let targets = Dictionary(uniqueKeysWithValues: mapped.map { ($0.name, $0.targets) })

        #expect(targets["Alamofire"] == ["Outer"])
        #expect(targets["SnapKit"] == ["Inner"])
        #expect(targets["Kingfisher"] == ["Outer"])
    }

    @Test("Computed target names are never inferred")
    func testComputedTargetIsNotMapped() {
        let content = """
        target target_name do
          pod 'Alamofire'
        end
        """
        let dependencies = [
            CocoaPodDependency(name: "Alamofire", version: "5.9.1", source: .registry, isDirect: true, targets: [])
        ]

        let mapped = PodfileTargetMapper().map(
            podfileContent: content,
            lockfileDependencies: dependencies
        )
        #expect(mapped.first?.targets.isEmpty == true)
    }

    @Test("Exact subspec names retain the literal target")
    func testSubspecMapping() {
        let content = """
        target :'My App' do
          pod 'Firebase/Analytics'
        end
        """
        let dependencies = [
            CocoaPodDependency(name: "Firebase/Analytics", version: "11.0.0", source: .registry, isDirect: true, targets: [])
        ]

        let mapped = PodfileTargetMapper().map(
            podfileContent: content,
            lockfileDependencies: dependencies
        )
        #expect(mapped.first?.targets == ["My App"])
    }
}
