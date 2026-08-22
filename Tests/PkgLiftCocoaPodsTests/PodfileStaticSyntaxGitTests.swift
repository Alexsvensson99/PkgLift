import Testing
@testable import PkgLiftCocoaPods
import PkgLiftCore

@Suite("PodfileStaticSyntax External Git Tests")
struct PodfileStaticSyntaxGitTests {
    @Test("Recognize bounded literal Git declarations")
    func testRecognizesBoundedLiteralGitDeclarations() {
        let cases: [(source: String, expected: PodfileStaticSyntax.ExternalGitSource)] = [
            (
                "pod 'HTTPKit', :git => 'https://example.invalid/Owner/HTTPKit.git', :commit => '0123456789abcdef0123456789abcdef01234567' # pinned",
                .supported(
                    url: "https://example.invalid/Owner/HTTPKit.git",
                    ref: .commit("0123456789abcdef0123456789abcdef01234567")
                )
            ),
            (
                "pod(\"SSHKit\", git: \"ssh://git@example.invalid/Owner/SSHKit.git\", tag: 'v1.2.3')",
                .supported(
                    url: "ssh://git@example.invalid/Owner/SSHKit.git",
                    ref: .tag("v1.2.3")
                )
            ),
            (
                "pod 'SCPKit', git: 'git@example.invalid:Owner/SCPKit.git', :branch => 'main'",
                .supported(
                    url: "git@example.invalid:Owner/SCPKit.git",
                    ref: .branch("main")
                )
            ),
            (
                "pod('UnpinnedKit', :git => 'https://example.invalid/Owner/UnpinnedKit.git')",
                .supported(url: "https://example.invalid/Owner/UnpinnedKit.git", ref: nil)
            ),
        ]

        for testCase in cases {
            #expect(PodfileStaticSyntax.externalGitSource(from: testCase.source) == testCase.expected)
        }
    }

    @Test("Leave registry-only declarations outside the Git grammar")
    func testRegistryDeclarationsReturnNone() {
        let cases = [
            "pod 'RegistryKit'",
            "pod('RegistryKit', '~> 1.0')",
            "pod 'RegistryKit', modular_headers: true # ordinary registry declaration",
            "pod 'RegistryKit' # migrate to git: later",
            "pod 'git:RegistryKit'",
            "pod 'RegistryKit', 'git:1.0'",
        ]

        for source in cases {
            #expect(PodfileStaticSyntax.externalGitSource(from: source) == .none)
        }
    }

    @Test("Reject Git syntax requiring evaluation or unsupported option combinations")
    func testRejectsUnsupportedGitSyntax() {
        let cases = [
            "pod 'DuplicateGit', :git => 'https://example.invalid/a.git', git: 'https://example.invalid/b.git'",
            "pod 'MultipleRefs', :git => 'https://example.invalid/a.git', :tag => 'v1', :commit => '0123456789abcdef0123456789abcdef01234567'",
            "pod 'PathAndGit', :git => 'https://example.invalid/a.git', :path => '../a'",
            "pod 'VersionAndGit', '1.0.0', :git => 'https://example.invalid/a.git'",
            "pod 'ExtraOption', :git => 'https://example.invalid/a.git', :submodules => true",
            "pod 'MalformedHashRocket', :git = 'https://example.invalid/a.git'",
            "pod 'VariableGit', :git => git_url",
            "pod 'InterpolatedGit', git: \"https://#{host}/a.git\"",
            "pod 'ExpressionTail', :git => 'https://example.invalid/a.git' + suffix",
            "pod 'SemicolonTail', :git => 'https://example.invalid/a.git'; puts 'side effect'",
            "pod('UnclosedParen', :git => 'https://example.invalid/a.git'",
            "pod 'Multiline', :git => 'https://example.invalid/a.git',\n  :tag => 'v1'",
        ]

        for source in cases {
            #expect(PodfileStaticSyntax.externalGitSource(from: source) == .unsupported)
        }
    }
}
