import Testing
import Foundation
@testable import PkgLiftCocoaPods
import PkgLiftCore

@Suite("PodfileParser Tests")
struct PodfileParserTests {
    @Test("Parse SimplePodfile")
    func testParseSimplePodfile() throws {
        let parser = PodfileParser()
        let content = """
        platform :ios, '14.0'
        use_frameworks!

        target 'MyApp' do
          pod 'Alamofire', '~> 5.6'
          pod 'SwiftyJSON', '~> 5.0'
        end
        """

        let (features, directDependencies, targets) = parser.parse(content: content)
        #expect(features.useFrameworks == true)
        #expect(features.hasDynamicRuby == false)
        #expect(directDependencies.count == 2)
        #expect(directDependencies.contains(where: { $0.name == "Alamofire" }))
        #expect(targets == ["MyApp"])
    }

    @Test("Parse Dynamic Ruby")
    func testParseDynamicRuby() throws {
        let parser = PodfileParser()
        let content = """
        require 'json'
        system('echo "Hello"')
        """
        let (features, _, _) = parser.parse(content: content)
        #expect(features.hasDynamicRuby == true)
    }

    @Test("Detect typed cross-platform integration calls without evaluating Ruby")
    func testDetectIntegrationMarkers() {
        let content = """
        target 'App' do
          use_react_native!(path: config[:reactNativePath])
          flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
          capacitor_pods()
          use_react_native!
        end
        """

        let (features, _, _) = PodfileParser().parse(content: content)

        #expect(features.integrationMarkers == [.reactNative, .flutter, .capacitor])
        #expect(features.hasRisks == true)
    }

    @Test("Ignore quoted commented and identifier-suffix integration marker text")
    func testIntegrationMarkerFalsePositives() {
        let content = #"""
        # use_react_native!
        puts "flutter_install_all_ios_pods"
        marker = 'capacitor_pods'
        foo_use_react_native!
        flutter_install_all_ios_pods_helper
        capacitor_pods_extra()
        """#

        let (features, _, _) = PodfileParser().parse(content: content)

        #expect(features.integrationMarkers.isEmpty)
    }

    @Test("Detect unsupported control flow before target mapping")
    func testDetectUnsupportedControlFlow() {
        let content = """
        pods = ['Alamofire']
        target 'MyApp' do
          pods.each do |name|
            pod name
          end
        end
        """

        let (features, dependencies, _) = PodfileParser().parse(content: content)
        #expect(features.hasDynamicRuby == true)
        #expect(dependencies.isEmpty)
    }

    @Test("Parse literal string, symbol, and escaped target names")
    func testParseLiteralTargetForms() {
        let content = #"""
        target 'Single' do
        end
        target "Double" do
        end
        target :Symbol do
        end
        target :'Quoted Symbol' do
        end
        target 'Team\'s App' do
        end
        target "Quoted \"App\"" do
        end
        """#

        let (features, _, targets) = PodfileParser().parse(content: content)
        #expect(features.hasDynamicRuby == false)
        #expect(targets == ["Single", "Double", "Symbol", "Quoted Symbol", "Team's App", "Quoted \"App\""])
    }

    @Test("Computed target and pod names remain dynamic")
    func testComputedNamesRemainDynamic() {
        let content = #"""
        target target_name do
          pod dependency_name
        end
        target :"My #{suffix}" do
        end
        target :"#@target" do
        end
        target :"#$target" do
        end
        target :MyApp do
          pod "#@dependency"
          pod "#$dependency"
        end
        """#

        let (features, dependencies, targets) = PodfileParser().parse(content: content)
        #expect(features.hasDynamicRuby == true)
        #expect(dependencies.isEmpty)
        #expect(targets == ["MyApp"])
    }

    @Test("Parse escaped literal pod names without interpolation")
    func testParseEscapedPodNames() {
        let content = #"""
        target :MyApp do
          pod 'Team\'sKit'
          pod "Quoted\"Kit"
        end
        """#

        let (features, dependencies, _) = PodfileParser().parse(content: content)
        #expect(features.hasDynamicRuby == false)
        #expect(dependencies.map(\.name) == ["Team'sKit", "Quoted\"Kit"])
    }

    @Test("Preserve literal declaration targets and external source in a Ruby-helper Podfile")
    func testBarkLikeDeclarationAttribution() throws {
        let fixture = try #require(Bundle.module.url(
            forResource: "Podfile",
            withExtension: nil,
            subdirectory: "Fixtures/BarkLikePodfile"
        ))

        let parsed = try PodfileParser().parse(fileURL: fixture)
        #expect(parsed.features.hasDynamicRuby == true)
        #expect(parsed.features.hasPostInstallHook == true)
        #expect(parsed.features.hasInheritSearchPaths == true)
        #expect(parsed.directDependencies.count == 6)

        let kingfisherDeclarations = parsed.directDependencies.filter { $0.name == "Kingfisher" }
        #expect(kingfisherDeclarations.map(\.targets) == [
            ["App", "WidgetExtension"],
            ["NotificationServiceExtension"],
            ["WidgetExtension"],
        ])
        #expect(kingfisherDeclarations.first?.effectiveTargetAttribution.status == .multiple)
        #expect(kingfisherDeclarations.first?.declarations?.count == 1)
        #expect(kingfisherDeclarations.first?.declarations?.first?.targetName == nil)

        let appOnly = try #require(parsed.directDependencies.first { $0.name == "Moya/RxSwift" })
        #expect(appOnly.targets == ["App"])
        #expect(appOnly.effectiveTargetAttribution.status == .exact)
        #expect(appOnly.declarations?.count == 1)

        let external = try #require(parsed.directDependencies.first { $0.name == "ExternalKit" })
        #expect(external.targets == ["App", "WidgetExtension"])
        #expect(external.effectiveTargetAttribution.status == .multiple)
        #expect(external.source == .git(
            url: "https://example.invalid/ExternalKit.git",
            ref: .branch("main")
        ))
    }

    @Test("Attribute a static parameterless helper to one literal target")
    func testSingleTargetHelperAttribution() throws {
        let content = """
        def tinode_pods()
          pod 'TinodeSDK'
        end

        target :Tinodios do
          tinode_pods()
        end
        """

        let parsed = PodfileParser().parse(content: content)
        let dependency = try #require(parsed.directDependencies.first)

        #expect(parsed.features.hasDynamicRuby == false)
        #expect(dependency.targets == ["Tinodios"])
        #expect(dependency.effectiveTargetAttribution.status == .exact)
        #expect(dependency.effectiveTargetAttribution.unresolvedDeclarationCount == 0)
        #expect(dependency.declarations?.count == 1)
        #expect(dependency.declarations?.first?.scope == .rubyHelper)
        #expect(dependency.declarations?.first?.scopeName == "tinode_pods")
        #expect(dependency.declarations?.first?.targetName == "Tinodios")
    }

    @Test("Allow static CocoaPods directives in a helper called from two targets")
    func testStaticHelperDirectivesPreserveMultipleAttribution() throws {
        let content = """
        def app_pods
          use_modular_headers!
          use_frameworks! :linkage => :static
          inhibit_all_warnings!()
          pod 'TinodeSDK'
        end

        target 'Tinodios' do
          app_pods
        end

        target 'TinodiosTests' do
          app_pods
        end
        """

        let parsed = PodfileParser().parse(content: content)
        let dependency = try #require(parsed.directDependencies.first)

        #expect(parsed.features.useModularHeaders == true)
        #expect(parsed.features.useFrameworks == true)
        #expect(parsed.features.hasDynamicRuby == false)
        #expect(dependency.targets == ["Tinodios", "TinodiosTests"])
        #expect(dependency.effectiveTargetAttribution.status == .multiple)
        #expect(dependency.effectiveTargetAttribution.unresolvedDeclarationCount == 0)
        #expect(dependency.declarations?.count == 1)
        #expect(dependency.declarations?.first?.targetName == nil)
    }

    @Test("Unknown dispatch makes every helper attribution partial")
    func testUnknownDispatchInvalidatesAllHelpers() throws {
        let content = """
        def app_pods
          pod 'AppPod'
        end

        def shared_pods
          pod 'SharedPod'
        end

        target 'Tinodios' do
          app_pods
          shared_pods
        end

        target 'DynamicTarget' do
          send(method_name)
          public_send(variable)
          __send__(:app_pods)
          method(variable).call
        end
        """

        let parsed = PodfileParser().parse(content: content)
        #expect(parsed.features.hasDynamicRuby == true)

        for name in ["AppPod", "SharedPod"] {
            let dependency = try #require(parsed.directDependencies.first { $0.name == name })
            #expect(dependency.targets == ["Tinodios"])
            #expect(dependency.effectiveTargetAttribution.status == .partial)
            #expect(dependency.effectiveTargetAttribution.unresolvedDeclarationCount == 1)
            #expect(dependency.declarations?.count == 1)
            #expect(dependency.declarations?.first?.targetName == nil)
        }
    }

    @Test("Literal send invalidates only the named helper")
    func testLiteralSendIsTargetedButUnresolved() throws {
        let content = """
        def exact_pods
          pod 'ExactPod'
        end

        def dispatched_pods
          pod 'DispatchedPod'
        end

        target 'Tinodios' do
          exact_pods
          send(:dispatched_pods)
        end
        """

        let parsed = PodfileParser().parse(content: content)
        #expect(parsed.features.hasDynamicRuby == true)

        let exact = try #require(parsed.directDependencies.first { $0.name == "ExactPod" })
        #expect(exact.targets == ["Tinodios"])
        #expect(exact.effectiveTargetAttribution.status == .exact)

        let dispatched = try #require(
            parsed.directDependencies.first { $0.name == "DispatchedPod" }
        )
        #expect(dispatched.targets.isEmpty)
        #expect(dispatched.effectiveTargetAttribution.status == .unresolved)
        #expect(dispatched.effectiveTargetAttribution.unresolvedDeclarationCount == 1)
    }

    @Test("Keep parameterized recursive conditional and receiver helper use unresolved")
    func testUnsafeHelperFormsRemainUnresolved() throws {
        let content = """
        def parameterized_pods(configuration)
          pod 'ParameterizedPod'
        end

        def recursive_pods
          pod 'RecursivePod'
          recursive_pods
        end

        def conditional_pods
          pod 'ConditionalPod'
        end

        def receiver_pods
          pod 'ReceiverPod'
        end

        def dynamic_framework_pods
          use_frameworks! linkage: framework_linkage
          pod 'DynamicFrameworkPod'
        end

        target 'App' do
          parameterized_pods(:debug)
          recursive_pods
          conditional_pods if enabled
          receiver_pods
          dynamic_framework_pods

          def nested_pods
            pod 'NestedPod'
          end
          nested_pods
        end

        target 'Widget' do
          self.receiver_pods
        end
        """

        let parsed = PodfileParser().parse(content: content)
        #expect(parsed.features.hasDynamicRuby == true)

        for name in [
            "ParameterizedPod",
            "RecursivePod",
            "ConditionalPod",
            "DynamicFrameworkPod",
            "NestedPod",
        ] {
            let dependency = try #require(parsed.directDependencies.first { $0.name == name })
            #expect(dependency.targets.isEmpty)
            #expect(dependency.effectiveTargetAttribution.status == .unresolved)
            #expect(dependency.effectiveTargetAttribution.unresolvedDeclarationCount == 1)
        }

        let receiver = try #require(
            parsed.directDependencies.first { $0.name == "ReceiverPod" }
        )
        #expect(receiver.targets == ["App"])
        #expect(receiver.effectiveTargetAttribution.status == .partial)
        #expect(receiver.effectiveTargetAttribution.unresolvedDeclarationCount == 1)
    }

    @Test("Reject unrepresentable pod syntax per dependency")
    func testUnsafePodOptionsDoNotDegradeSafeDeclarations() throws {
        let content = """
        target 'App' do
          pod 'SafePod'
          pod 'VersionedPod', '~> 1.2'
          pod 'ModularPod', '~> 5.0', modular_headers: true
          pod 'LegacyModularPod', :modular_headers => true
          pod 'ConditionalPod' if enabled
          pod 'UnlessPod' unless disabled
          pod 'ConfiguredPod', :configurations => ['Debug']
          pod 'NonModularPod', modular_headers: false
          pod 'DynamicModularPod', modular_headers: enabled
          pod 'DynamicVersionPod', version_name
          pod 'SemicolonPod'; puts 'side effect'
          pod 'ExternalPod', :git => 'https://example.invalid/ExternalPod.git'
        end
        """

        let parsed = PodfileParser().parse(content: content)
        #expect(parsed.features.hasDynamicRuby == false)

        for name in ["SafePod", "VersionedPod", "ModularPod", "LegacyModularPod"] {
            let dependency = try #require(parsed.directDependencies.first { $0.name == name })
            #expect(dependency.source == .registry)
            #expect(dependency.targets == ["App"])
            #expect(dependency.effectiveTargetAttribution.status == .exact)
        }

        for name in [
            "ConditionalPod",
            "UnlessPod",
            "ConfiguredPod",
            "NonModularPod",
            "DynamicModularPod",
            "DynamicVersionPod",
            "SemicolonPod",
        ] {
            let dependency = try #require(parsed.directDependencies.first { $0.name == name })
            #expect(dependency.source == .unknown)
            #expect(dependency.targets == ["App"])
        }

        let external = try #require(
            parsed.directDependencies.first { $0.name == "ExternalPod" }
        )
        #expect(external.source == .git(
            url: "https://example.invalid/ExternalPod.git",
            ref: nil
        ))
        #expect(external.targets == ["App"])
    }

    @Test("Parent declarations include default and complete nested targets")
    func testNestedTargetsInheritParentPodsByDefault() throws {
        let content = """
        target 'ParentApp' do
          pod 'ParentPod'

          target 'DefaultChild' do
            pod 'DefaultChildPod'
          end

          target 'CompleteChild' do
            inherit! :complete
          end
        end
        """

        let parsed = PodfileParser().parse(content: content)
        let parent = try #require(
            parsed.directDependencies.first { $0.name == "ParentPod" }
        )
        #expect(parent.targets == ["CompleteChild", "DefaultChild", "ParentApp"])
        #expect(parent.effectiveTargetAttribution.status == .multiple)
        #expect(parent.declarations?.first?.targetName == nil)

        let child = try #require(
            parsed.directDependencies.first { $0.name == "DefaultChildPod" }
        )
        #expect(child.targets == ["DefaultChild"])
        #expect(child.effectiveTargetAttribution.status == .exact)
    }

    @Test("Search-path inheritance excludes parent dependencies")
    func testSearchPathsDoesNotInheritParentPods() throws {
        let content = """
        target 'ParentApp' do
          pod 'ParentPod'

          target 'Tests' do
            inherit! :search_paths
          end
        end
        """

        let parsed = PodfileParser().parse(content: content)
        let parent = try #require(parsed.directDependencies.first)

        #expect(parsed.features.hasInheritSearchPaths == true)
        #expect(parent.targets == ["ParentApp"])
        #expect(parent.effectiveTargetAttribution.status == .exact)
        #expect(parent.declarations?.first?.targetName == "ParentApp")
    }

    @Test("A helper called in a parent includes default nested targets")
    func testParentHelperCallIncludesNestedTarget() throws {
        let content = """
        def app_pods
          pod 'SharedPod'
        end

        target 'ParentApp' do
          app_pods

          target 'ChildApp' do
          end
        end
        """

        let parsed = PodfileParser().parse(content: content)
        let dependency = try #require(parsed.directDependencies.first)

        #expect(dependency.targets == ["ChildApp", "ParentApp"])
        #expect(dependency.effectiveTargetAttribution.status == .multiple)
        #expect(dependency.declarations?.count == 1)
        #expect(dependency.declarations?.first?.targetName == nil)
    }
}
