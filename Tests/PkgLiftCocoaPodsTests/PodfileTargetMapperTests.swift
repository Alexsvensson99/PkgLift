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

        #expect(targets["Alamofire"] == ["Inner", "Outer"])
        #expect(targets["SnapKit"] == ["Inner"])
        #expect(targets["Kingfisher"] == ["Inner", "Outer"])

        let conditional = mapped.first { $0.name == "Alamofire" }
        #expect(conditional?.effectiveTargetAttribution.status == .partial)
        #expect(conditional?.effectiveTargetAttribution.unresolvedDeclarationCount == 1)

        let kingfisher = mapped.first { $0.name == "Kingfisher" }
        #expect(kingfisher?.effectiveTargetAttribution.status == .multiple)
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

    @Test("Use only exact declarations and bounded static helper call sites")
    func testBarkLikeExactTargetMapping() throws {
        let podfileURL = try #require(Bundle.module.url(
            forResource: "Podfile",
            withExtension: nil,
            subdirectory: "Fixtures/BarkLikePodfile"
        ))
        let lockfileURL = try #require(Bundle.module.url(
            forResource: "Podfile",
            withExtension: "lock",
            subdirectory: "Fixtures/BarkLikePodfile"
        ))
        let content = try String(contentsOf: podfileURL, encoding: .utf8)
        let lockDependencies = try PodfileLockParser().parse(fileURL: lockfileURL)

        let mapped = PodfileTargetMapper().map(
            podfileContent: content,
            lockfileDependencies: lockDependencies
        )

        #expect(mapped.first { $0.name == "Kingfisher" }?.targets == [
            "App",
            "NotificationServiceExtension",
            "WidgetExtension",
        ])
        #expect(
            mapped.first { $0.name == "Kingfisher" }?.effectiveTargetAttribution.status
                == .multiple
        )
        #expect(mapped.first { $0.name == "Kingfisher" }?.declarations?.count == 3)
        #expect(mapped.first { $0.name == "Moya" }?.targets == ["NotificationServiceExtension"])
        #expect(mapped.first { $0.name == "Moya/Core" }?.targets == [])
        #expect(mapped.first { $0.name == "Moya/RxSwift" }?.targets == ["App"])
        #expect(
            mapped.first { $0.name == "Moya/RxSwift" }?.effectiveTargetAttribution.status
                == .exact
        )
        #expect(mapped.first { $0.name == "Moya/RxSwift" }?.declarations?.count == 1)
        #expect(
            mapped.first { $0.name == "Moya/RxSwift" }?.declarations?.first?.targetName
                == "App"
        )

        let external = try #require(mapped.first { $0.name == "ExternalKit" })
        #expect(external.targets == ["App", "WidgetExtension"])
        #expect(external.effectiveTargetAttribution.status == .multiple)
        #expect(external.declarations?.count == 1)
        #expect(external.declarations?.first?.targetName == nil)
    }

    @Test("Aggregate one helper origin without cloning it per target call site")
    func testMultipleTargetHelperPreservesDeclarationOrigin() throws {
        let content = """
        def shared_pods
          use_modular_headers!
          pod 'TinodeSDK'
        end

        target 'Tinodios' do
          shared_pods
        end

        target 'TinodiosShare' do
          shared_pods
        end
        """
        let lockDependencies = [
            CocoaPodDependency(
                name: "TinodeSDK",
                version: "1.0.0",
                source: .registry,
                isDirect: true
            )
        ]

        let mapped = PodfileTargetMapper().map(
            podfileContent: content,
            lockfileDependencies: lockDependencies
        )
        let dependency = try #require(mapped.first)

        #expect(dependency.targets == ["Tinodios", "TinodiosShare"])
        #expect(dependency.effectiveTargetAttribution.status == .multiple)
        #expect(dependency.effectiveTargetAttribution.unresolvedDeclarationCount == 0)
        #expect(dependency.declarations?.count == 1)
        #expect(dependency.declarations?.first?.scope == .rubyHelper)
        #expect(dependency.declarations?.first?.targetName == nil)
    }

    @Test("Aggregate proven and dynamic helper calls as partial")
    func testPartialHelperAttributionSurvivesAggregation() throws {
        let content = """
        def shared_pods
          pod 'TinodeSDK'
        end

        target 'Tinodios' do
          shared_pods
        end

        target 'TinodiosShare' do
          public_send(:shared_pods)
        end
        """
        let lockDependencies = [
            CocoaPodDependency(
                name: "TinodeSDK",
                version: "1.0.0",
                source: .registry,
                isDirect: true
            )
        ]

        let mapped = PodfileTargetMapper().map(
            podfileContent: content,
            lockfileDependencies: lockDependencies
        )
        let dependency = try #require(mapped.first)

        #expect(dependency.targets == ["Tinodios"])
        #expect(dependency.effectiveTargetAttribution.status == .partial)
        #expect(dependency.effectiveTargetAttribution.unresolvedDeclarationCount == 1)
        #expect(dependency.declarations?.count == 1)
    }
}
