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
}
