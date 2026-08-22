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

    @Test("Parse statically bounded parenthesized target and pod declarations")
    func testParenthesizedLiteralDeclarations() throws {
        let content = """
        target('MyApp') do
          pod('Alamofire')
          pod("SnapKit", "~> 5.7")
          pod('ModularPod', modular_headers: true)
          pod('LegacyModularPod', '~> 1.0', :modular_headers => true)
        end
        """

        let parsed = PodfileParser().parse(content: content)

        #expect(parsed.features.hasDynamicRuby == false)
        #expect(parsed.targets == ["MyApp"])
        #expect(parsed.directDependencies.map(\.name) == [
            "Alamofire",
            "SnapKit",
            "ModularPod",
            "LegacyModularPod",
        ])
        for dependency in parsed.directDependencies {
            #expect(dependency.source == .registry)
            #expect(dependency.targets == ["MyApp"])
            #expect(dependency.effectiveTargetAttribution.status == .exact)
            #expect(dependency.hasLiteralMigrationProvenance)
        }
    }

    @Test("Reject unsafe or unbalanced parenthesized declarations")
    func testUnsafeParenthesizedDeclarationsFailClosed() throws {
        let content = #"""
        target('App') do
          pod('ConditionalPod') if enabled
          pod('VariablePod', version_name)
          pod('ExternalOptionsPod', '~> 1.0', configurations: ['Debug'])
          pod('ExtraArgumentPod', '~> 1.0', modular_headers: true, extra: true)
          pod('ExternalPod', git: 'https://example.invalid/ExternalPod.git')
          pod("Interpolated#{suffix}")
          pod('SemicolonPod'); puts 'side effect'
          pod('UnbalancedPod'
        end
        """#

        let parsed = PodfileParser().parse(content: content)

        #expect(parsed.features.hasDynamicRuby)
        for name in [
            "ConditionalPod",
            "VariablePod",
            "ExternalOptionsPod",
            "ExtraArgumentPod",
            "SemicolonPod",
            "UnbalancedPod",
        ] {
            let dependency = try #require(parsed.directDependencies.first { $0.name == name })
            #expect(dependency.source == .unknown)
            #expect(dependency.hasLiteralMigrationProvenance == false)
        }
        #expect(parsed.directDependencies.contains { $0.name == "Interpolated#{suffix}" } == false)
        let external = try #require(parsed.directDependencies.first { $0.name == "ExternalPod" })
        #expect(external.source == .git(
            url: "https://example.invalid/ExternalPod",
            ref: nil
        ))
        #expect(external.hasLiteralMigrationProvenance == false)
        guard case .git(let provenance)? = external.sourceProvenance else {
            Issue.record("Expected typed Git provenance")
            return
        }
        #expect(provenance.status == .ambiguousRepository)
        #expect(provenance.declarations.count == 1)
        #expect(
            provenance.declarations.first?.repository.identity?.value
                == "https://example.invalid/ExternalPod"
        )

        let unbalancedTarget = PodfileParser().parse(content: """
        target('Broken' do
          pod('Alamofire')
        end
        """)
        #expect(unbalancedTarget.features.hasDynamicRuby)
        #expect(unbalancedTarget.directDependencies.first?.effectiveTargetAttribution.status == .unresolved)

        let missingSeparator = PodfileParser().parse(content: """
        target('Broken')do
          pod('Alamofire')
        end
        """)
        #expect(missingSeparator.features.hasDynamicRuby)
        #expect(missingSeparator.directDependencies.first?.effectiveTargetAttribution.status == .unresolved)
    }

    @Test("Fail closed project-wide for external and extra pod options")
    func testExternalAndExtraOptionsCreateProjectWideDynamicRisk() throws {
        let parsed = PodfileParser().parse(content: """
        target('App') do
          pod('ConfiguredPod', configurations: ['Debug'])
          pod('ExtraArgumentPod', '1.0.0', foo: true)
          pod('ExternalPod', git: 'https://example.invalid/ExternalPod.git')
          pod('SafePod', '1.0.0')
        end
        """)

        #expect(parsed.features.hasDynamicRuby)
        for name in ["ConfiguredPod", "ExtraArgumentPod"] {
            let dependency = try #require(parsed.directDependencies.first { $0.name == name })
            #expect(dependency.source == .unknown)
            #expect(dependency.hasLiteralMigrationProvenance == false)
        }
        let external = try #require(parsed.directDependencies.first { $0.name == "ExternalPod" })
        #expect(external.source == .git(url: "https://example.invalid/ExternalPod", ref: nil))
        #expect(external.hasLiteralMigrationProvenance == false)
        guard case .git(let provenance)? = external.sourceProvenance else {
            Issue.record("Expected typed Git provenance")
            return
        }
        #expect(provenance.status == .ambiguousRepository)
        let safe = try #require(parsed.directDependencies.first { $0.name == "SafePod" })
        #expect(safe.source == .registry)
        #expect(safe.hasLiteralMigrationProvenance)
    }

    @Test("Model bounded external Git declarations without Ruby execution")
    func testBoundedExternalGitDeclarationCreatesTypedProvenance() throws {
        let parsed = PodfileParser().parse(content: """
        target 'App' do
          pod 'BranchPod', :git => 'https://EXAMPLE.invalid/Owner/BranchPod.git', :branch => 'main'
          pod 'TagPod', git: 'git@example.invalid:Owner/TagPod.git', tag: '1.2.3'
          pod 'UnpinnedPod', git: 'ssh://git@example.invalid/Owner/UnpinnedPod.git'
        end
        """)

        #expect(parsed.features.hasDynamicRuby == false)
        let expectedStatuses: [String: GitSourceEvidenceStatus] = [
            "BranchPod": .mutable,
            "TagPod": .incomplete,
            "UnpinnedPod": .unpinned,
        ]
        for (name, expectedStatus) in expectedStatuses {
            let dependency = try #require(parsed.directDependencies.first { $0.name == name })
            #expect(dependency.targets == ["App"])
            #expect(dependency.effectiveTargetAttribution.status == .exact)
            #expect(dependency.hasLiteralMigrationProvenance == false)
            guard case .git(let provenance)? = dependency.sourceProvenance else {
                Issue.record("Expected typed Git provenance for \(name)")
                continue
            }
            #expect(provenance.status == expectedStatus)
        }
    }

    @Test("Unsupported external Git option combinations fail closed")
    func testUnsupportedExternalGitSyntaxFailsClosed() throws {
        let parsed = PodfileParser().parse(content: """
        target 'App' do
          pod 'ConflictingPod', git: 'https://example.invalid/Owner/Repo.git', branch: 'main', tag: '1.0.0'
          pod 'MixedSourcePod', git: 'https://example.invalid/Owner/Repo.git', path: '../Repo'
        end
        """)

        #expect(parsed.features.hasDynamicRuby)
        for dependency in parsed.directDependencies {
            #expect(dependency.source == .unknown)
            #expect(dependency.hasLiteralMigrationProvenance == false)
            guard case .git(let provenance)? = dependency.sourceProvenance else {
                Issue.record("Expected unsupported Git provenance")
                continue
            }
            #expect(provenance.status == .unsupportedSyntax)
        }
    }

    @Test("Credential-bearing Git declarations are sanitized before standard JSON")
    func testCredentialBearingGitDeclarationNeverLeaksThroughStandardJSON() throws {
        let parsed = PodfileParser().parse(content: """
        target 'App' do
          pod 'PrivatePod', git: 'https://alice:password@example.invalid/Owner/Repo.git?token=supersecret#private', tag: '1.0.0'
        end
        """)
        let dependency = try #require(parsed.directDependencies.first)

        #expect(dependency.source == .git(
            url: "https://example.invalid/Owner/Repo",
            ref: .tag("1.0.0")
        ))
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected credential-bearing Git provenance")
            return
        }
        #expect(provenance.status == .credentialBearing)

        let json = try #require(String(
            data: JSONEncoder().encode(dependency),
            encoding: .utf8
        ))
        for secret in ["alice", "password", "token", "supersecret", "private"] {
            #expect(json.contains(secret) == false)
        }
    }

    @Test("Fail closed for parenthesized declarations inside unsupported Ruby blocks")
    func testParenthesizedDeclarationInsideUnknownBlockFailsClosed() throws {
        let parsed = PodfileParser().parse(content: """
        target('App') do
          [].each do # zero iterations: Ruby never executes this body
            pod('SDWebImage', '5.18.1', modular_headers: true)
          end
        end
        """)

        let dependency = try #require(
            parsed.directDependencies.first { $0.name == "SDWebImage" }
        )
        #expect(parsed.features.hasDynamicRuby)
        #expect(dependency.effectiveTargetAttribution.status == .partial)
        #expect(dependency.hasLiteralMigrationProvenance == false)
    }

    @Test("Ignore non-executable Ruby comment and data regions")
    func testNonExecutableRubyRegionsAreIgnored() {
        let parsed = PodfileParser().parse(content: """
        =begin documentation
        target('Commented') do
          pod('CommentedPod')
        end
        =end

        target('App') do
          pod('RealPod')
        end

        __END__
        target('Data') do
          pod('DataPod')
        end
        """)

        #expect(parsed.features.hasDynamicRuby == false)
        #expect(parsed.targets == ["App"])
        #expect(parsed.directDependencies.map(\.name) == ["RealPod"])
    }

    @Test("Fail closed for quoted non-identifier heredocs and Ruby brace blocks")
    func testAdditionalUnsupportedRubyFormsFailClosed() throws {
        let heredoc = PodfileParser().parse(content: """
        target('App') do
          puts <<~'1'
            pod('SDWebImage', '5.18.1', modular_headers: true)
          1
        end
        """)
        #expect(heredoc.features.hasDynamicRuby)

        let braceBlock = PodfileParser().parse(content: """
        target('App') do
          [].each {
            pod('SDWebImage', '5.18.1', modular_headers: true)
          }
        end
        """)
        let dependency = try #require(
            braceBlock.directDependencies.first { $0.name == "SDWebImage" }
        )
        #expect(braceBlock.features.hasDynamicRuby)
        #expect(dependency.hasLiteralMigrationProvenance)
    }

    @Test("Fail closed for multiline literals and continuation expressions")
    func testCrossLineRubySyntaxFailsClosed() throws {
        let podfiles = [
            """
            puts "
            target('App') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            "
            """,
            """
            target('App') do
              false &&
                pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            puts %q(
            target('App') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            )
            """,
            """
            defined?(
              pod('SDWebImage', '5.18.1', modular_headers: true)
            )
            """,
        ]

        for podfile in podfiles {
            let parsed = PodfileParser().parse(content: podfile)
            #expect(parsed.features.hasDynamicRuby)
            #expect(parsed.directDependencies.contains { $0.name == "SDWebImage" })
        }
    }

    @Test("Fail closed for unmodeled executable statements")
    func testUnmodeledExecutableStatementsFailClosed() {
        let statements = [
            "next",
            "break",
            "raise 'stop'",
            "puts 'unmodeled call'",
            "pod('GuardPod'); next",
            "pod('GuardPod', false ? nil:abort)",
            "pod('GuardPod'), :foo",
            "pod('GuardPod', Kernel::abort)",
            "pod('GuardPod', 08)",
            "pod('GuardPod', foo: true)",
            "source 'https://private.example.invalid/specs'",
            "workspace 'OtherWorkspace'",
            "project 'Other.xcodeproj'",
        ]

        for statement in statements {
            let parsed = PodfileParser().parse(content: """
            target('App') do
              \(statement)
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """)

            #expect(parsed.features.hasDynamicRuby)
            #expect(parsed.directDependencies.contains { $0.name == "SDWebImage" })
        }
    }

    @Test("Fail closed without recursive parsing for deeply nested extra options")
    func testDeeplyNestedExtraOptionsDoNotExhaustParserStack() {
        let depth = 10_000
        let nestedLiteral = String(repeating: "[", count: depth)
            + "nil"
            + String(repeating: "]", count: depth)
        let parsed = PodfileParser().parse(content: """
        target('App') do
          pod('GuardPod', \(nestedLiteral))
          pod('SDWebImage', '5.18.1', modular_headers: true)
        end
        """)

        #expect(parsed.features.hasDynamicRuby)
        #expect(parsed.directDependencies.contains { $0.name == "GuardPod" })
        #expect(parsed.directDependencies.contains { $0.name == "SDWebImage" })
    }

    @Test("Reject raw control characters across active physical lines")
    func testRawControlCharactersFailClosed() {
        let podfiles = [
            """
            target('App') do
              pod('Guard\u{0}Pod')
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            source 'https://example.invalid/specs\u{0}'
            target('App') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
            """
            target('App') do # unsafe\u{0}comment
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """,
        ]

        for podfile in podfiles {
            let parsed = PodfileParser().parse(content: podfile)
            #expect(parsed.features.hasDynamicRuby)
            #expect(parsed.directDependencies.contains { $0.name == "SDWebImage" })
            #expect(parsed.directDependencies.contains { $0.name == "Guard\u{0}Pod" } == false)
        }
    }

    @Test("Reject non-ASCII whitespace at Ruby syntax boundaries")
    func testUnicodeWhitespaceFailsClosed() throws {
        let parsed = PodfileParser().parse(content: """
        target('App')\u{00A0}do
          pod('SDWebImage', '5.18.1', modular_headers: true)
        end
        """)
        let dependency = try #require(
            parsed.directDependencies.first { $0.name == "SDWebImage" }
        )

        #expect(parsed.features.hasDynamicRuby)
        #expect(dependency.effectiveTargetAttribution.status == .unresolved)

        let tabSeparated = PodfileParser().parse(content: """
        target('App')\tdo
          pod('SDWebImage', '5.18.1', modular_headers: true)
        end
        """)
        #expect(tabSeparated.features.hasDynamicRuby == false)
        #expect(tabSeparated.directDependencies.first?.effectiveTargetAttribution.status == .exact)
    }

    @Test("Do not split Ruby comments at Unicode line separators")
    func testUnicodeLineSeparatorsCannotCreateSyntheticDeclarations() {
        for separator in ["\u{0085}", "\u{2028}", "\u{2029}"] {
            let parsed = PodfileParser().parse(content:
                "# ignored\(separator)target('App') do\(separator)"
                    + "pod('SDWebImage', '5.18.1', modular_headers: true)\(separator)end\n"
            )

            #expect(parsed.features.hasDynamicRuby)
            #expect(parsed.targets.isEmpty)
            #expect(parsed.directDependencies.isEmpty)
        }
    }

    @Test("Keep non-ASCII embedded-document closers inside the Ruby comment")
    func testUnicodeEmbeddedDocumentCloserCannotCreateSyntheticDeclarations() {
        let parsed = PodfileParser().parse(content:
            "=begin\n"
                + "=end\u{00A0}\n"
                + "target('App') do\n"
                + "  pod('SDWebImage', '5.18.1', modular_headers: true)\n"
                + "end\n"
                + "=end\n"
        )

        #expect(parsed.features.hasDynamicRuby == false)
        #expect(parsed.targets.isEmpty)
        #expect(parsed.directDependencies.isEmpty)
    }

    @Test("Treat CRLF as Ruby physical line endings")
    func testCRLFPhysicalLinesPreserveStaticEvidence() throws {
        let parsed = PodfileParser().parse(content:
            "target('App') do\r\n"
                + "  pod('SDWebImage', '5.18.1', modular_headers: true)\r\n"
                + "end\r\n"
        )
        let dependency = try #require(
            parsed.directDependencies.first { $0.name == "SDWebImage" }
        )

        #expect(parsed.features.hasDynamicRuby == false)
        #expect(parsed.targets == ["App"])
        #expect(dependency.effectiveTargetAttribution.status == .exact)
        #expect(dependency.effectiveTargetAttribution.targets == ["App"])
    }

    @Test("Fail closed without recursive resolution for excessive target nesting")
    func testDeeplyNestedTargetsDoNotExhaustParserStack() throws {
        let depth = 10_000
        var lines: [String] = []
        lines.reserveCapacity(depth * 4 + 1)
        for index in 0..<depth {
            lines.append("target('T\(index)') do")
            lines.append("puts 'unmodeled'")
            lines.append("pod('Guard\(index)')")
        }
        lines.append("pod('SDWebImage', '5.18.1', modular_headers: true)")
        lines.append(contentsOf: repeatElement("end", count: depth))

        let parsed = PodfileParser().parse(content: lines.joined(separator: "\n"))
        let dependency = try #require(
            parsed.directDependencies.first { $0.name == "SDWebImage" }
        )

        #expect(parsed.features.hasDynamicRuby)
        #expect(parsed.targets.count == depth)
        #expect(parsed.directDependencies.count == depth + 1)
        #expect(dependency.effectiveTargetAttribution.status == .unresolved)
    }

    @Test("Reject unterminated block comments and unbalanced Ruby scopes")
    func testUnbalancedRubyStructureFailsClosed() {
        let missingEnd = PodfileParser().parse(content: """
        target('App') do
          pod('SDWebImage')
        """)
        #expect(missingEnd.features.hasDynamicRuby)

        let extraEnd = PodfileParser().parse(content: """
        target('App') do
          pod('SDWebImage')
        end
        end
        """)
        #expect(extraEnd.features.hasDynamicRuby)

        let unterminatedComment = PodfileParser().parse(content: """
        =begin documentation
        target('App') do
          pod('SDWebImage')
        end
        """)
        #expect(unterminatedComment.features.hasDynamicRuby)
        #expect(unterminatedComment.directDependencies.isEmpty)

        let indentedComment = PodfileParser().parse(content: """
        target('App') do
          =begin documentation
          ignored
          =end
          pod('SDWebImage')
        end
        """)
        #expect(indentedComment.features.hasDynamicRuby)
        #expect(indentedComment.directDependencies.contains { $0.name == "SDWebImage" })

        let indentedData = PodfileParser().parse(content: """
        target('App') do
          __END__
          pod('SDWebImage')
        end
        """)
        #expect(indentedData.features.hasDynamicRuby)
        #expect(indentedData.directDependencies.contains { $0.name == "SDWebImage" })
    }

    @Test("Reject helpers that shadow modeled CocoaPods DSL methods")
    func testModeledDSLHelperShadowingFailsClosed() {
        for helperName in ["pod", "target", "abstract_target"] {
            let parsed = PodfileParser().parse(content: """
            def \(helperName)
            end

            target('App') do
              pod('SDWebImage', '5.18.1', modular_headers: true)
            end
            """)

            #expect(parsed.features.hasDynamicRuby)
            #expect(parsed.directDependencies.contains { $0.name == "SDWebImage" })
        }
    }

    @Test("Heredoc syntax prevents automatic static evidence")
    func testHeredocFailsClosed() {
        let parsed = PodfileParser().parse(content: """
        target('App') do
          puts <<~PODS
            pod('SDWebImage')
          PODS
        end
        """)

        #expect(parsed.features.hasDynamicRuby)
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
            url: "https://example.invalid/ExternalKit",
            ref: .branch("main")
        ))
        guard case .git(let provenance)? = external.sourceProvenance else {
            Issue.record("Expected typed Git provenance")
            return
        }
        #expect(provenance.status == .ambiguousRepository)
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
    func testUnsafePodOptionsRemainPerDependencyWhileReachabilityRisksAreGlobal() throws {
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
        #expect(parsed.features.hasDynamicRuby)

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
            url: "https://example.invalid/ExternalPod",
            ref: nil
        ))
        #expect(external.targets == ["App"])
        guard case .git(let provenance)? = external.sourceProvenance else {
            Issue.record("Expected typed Git provenance")
            return
        }
        #expect(provenance.status == .ambiguousRepository)
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
