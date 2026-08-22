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

    @Test("Keep external tag declaration separate from checkout commit")
    func testExternalTagKeepsDeclarationRefSeparateFromCheckoutCommit() throws {
        let commit = String(repeating: "a", count: 40)
        let yaml = """
        PODS:
          - ExternalKit (1.0.0)
        DEPENDENCIES:
          - ExternalKit
        EXTERNAL SOURCES:
          ExternalKit:
            :tag: 1.0.0
            :git: https://EXAMPLE.invalid/Owner/ExternalKit.git
        CHECKOUT OPTIONS:
          ExternalKit:
            :commit: \(commit)
            :git: https://example.invalid/Owner/ExternalKit.git
        """

        let dependency = try #require(PodfileLockParser().parse(content: yaml).first)
        #expect(dependency.source == .git(
            url: "https://example.invalid/Owner/ExternalKit",
            ref: .tag("1.0.0")
        ))
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected Git lockfile provenance")
            return
        }
        #expect(provenance.status == .incomplete)
        #expect(provenance.declarations.isEmpty)
        #expect(provenance.lockfile?.externalSourceReference?.kind == .tag)
        #expect(provenance.lockfile?.externalSourceReference?.value == "1.0.0")
        #expect(provenance.lockfile?.checkoutReference?.kind == .commit)
        #expect(provenance.lockfile?.checkoutReference?.value == commit)
        #expect(provenance.lockfile?.checkoutReference?.isFullCheckoutCommit == true)
    }

    @Test("Credential-bearing lockfile URLs are sanitized before standard JSON")
    func testCredentialBearingLockfileURLIsSanitized() throws {
        let yaml = """
        PODS:
          - PrivateKit (1.0.0)
        DEPENDENCIES:
          - PrivateKit
        EXTERNAL SOURCES:
          PrivateKit:
            :branch: main
            :git: https://alice:password@example.invalid/Owner/PrivateKit.git?token=supersecret#private
        CHECKOUT OPTIONS:
          PrivateKit:
            :branch: main
            :git: https://alice:password@example.invalid/Owner/PrivateKit.git?token=supersecret#private
        """

        let dependency = try #require(PodfileLockParser().parse(content: yaml).first)
        #expect(dependency.source == .git(
            url: "https://example.invalid/Owner/PrivateKit",
            ref: .branch("main")
        ))
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected Git lockfile provenance")
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

    @Test("Conflicting external reference keys do not use precedence")
    func testConflictingExternalReferenceKeysRemainConflicting() throws {
        let yaml = """
        PODS:
          - ExternalKit (1.0.0)
        DEPENDENCIES:
          - ExternalKit
        EXTERNAL SOURCES:
          ExternalKit:
            :branch: main
            :tag: 1.0.0
            :git: https://example.invalid/Owner/ExternalKit.git
        """

        let dependency = try #require(PodfileLockParser().parse(content: yaml).first)
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected Git lockfile provenance")
            return
        }
        #expect(provenance.status == .conflicting)
        #expect(provenance.lockfile?.externalSourceReference == nil)
        #expect(provenance.lockfile?.hasConflictingEvidence == true)
    }

    @Test("Malformed external source and checkout sections are rejected")
    func testMalformedExternalSectionsAreRejected() {
        let malformedSections = [
            """
            PODS:
              - ExternalKit (1.0.0)
            EXTERNAL SOURCES:
              - not-a-mapping
            """,
            """
            PODS:
              - ExternalKit (1.0.0)
            CHECKOUT OPTIONS:
              ExternalKit: not-an-options-mapping
            """,
            """
            PODS:
              - ExternalKit (1.0.0)
            EXTERNAL SOURCES:
              ExternalKit:
                :git: https://example.invalid/Owner/First.git
                :git: https://example.invalid/Owner/Second.git
            """,
        ]

        for yaml in malformedSections {
            #expect(throws: PodfileLockParser.Error.self) {
                try PodfileLockParser().parse(content: yaml)
            }
        }
    }

    @Test("Unknown Git lockfile options remain incomplete")
    func testUnknownGitLockfileOptionRemainsIncomplete() throws {
        let yaml = """
        PODS:
          - ExternalKit (1.0.0)
        EXTERNAL SOURCES:
          ExternalKit:
            :git: https://example.invalid/Owner/ExternalKit.git
            :custom_option: value
        """

        let dependency = try #require(PodfileLockParser().parse(content: yaml).first)
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected Git lockfile provenance")
            return
        }
        #expect(provenance.status == .incomplete)
        #expect(provenance.lockfile?.hasMalformedEvidence == true)
    }

    @Test("Non-string Git repositories remain malformed without invented URL evidence")
    func testNonStringGitRepositoriesRemainMalformed() throws {
        let externalYAML = """
        PODS:
          - ExternalKit (1.0.0)
        EXTERNAL SOURCES:
          ExternalKit:
            :git: 42
        """

        let externalDependency = try #require(
            PodfileLockParser().parse(content: externalYAML).first
        )
        #expect(externalDependency.source == .unknown)
        guard case .git(let externalProvenance)? = externalDependency.sourceProvenance else {
            Issue.record("Expected malformed external Git lockfile provenance")
            return
        }
        #expect(externalProvenance.status == .incomplete)
        #expect(externalProvenance.lockfile?.externalSourceRepository == nil)
        #expect(externalProvenance.lockfile?.hasMalformedEvidence == true)
        let externalJSON = try #require(String(
            data: JSONEncoder().encode(externalDependency),
            encoding: .utf8
        ))
        #expect(externalJSON.contains("42") == false)
        #expect(externalJSON.contains(GitRepositoryEvidence.redactedDisplayURL) == false)

        let checkoutYAML = """
        PODS:
          - ExternalKit (1.0.0)
        EXTERNAL SOURCES:
          ExternalKit:
            :git: https://example.invalid/Owner/ExternalKit.git
        CHECKOUT OPTIONS:
          ExternalKit:
            :git: 42
        """

        let checkoutDependency = try #require(
            PodfileLockParser().parse(content: checkoutYAML).first
        )
        #expect(checkoutDependency.source == .git(
            url: "https://example.invalid/Owner/ExternalKit",
            ref: nil
        ))
        guard case .git(let checkoutProvenance)? = checkoutDependency.sourceProvenance else {
            Issue.record("Expected malformed checkout Git lockfile provenance")
            return
        }
        #expect(checkoutProvenance.status == .incomplete)
        #expect(checkoutProvenance.lockfile?.externalSourceRepository != nil)
        #expect(checkoutProvenance.lockfile?.checkoutRepository == nil)
        #expect(checkoutProvenance.lockfile?.hasMalformedEvidence == true)
    }

    @Test("Unsupported string Git repositories remain unsupported URLs")
    func testUnsupportedStringGitRepositoryRemainsUnsupported() throws {
        let yaml = """
        PODS:
          - ExternalKit (1.0.0)
        EXTERNAL SOURCES:
          ExternalKit:
            :git: http://example.invalid/Owner/ExternalKit.git
        """

        let dependency = try #require(PodfileLockParser().parse(content: yaml).first)
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected unsupported Git lockfile provenance")
            return
        }
        #expect(provenance.status == .unsupportedURL)
        #expect(provenance.lockfile?.hasMalformedEvidence == false)
        #expect(provenance.lockfile?.externalSourceRepository?.status == .unsupportedURL)
    }

    @Test("Short checkout commits remain incomplete evidence")
    func testShortCheckoutCommitRemainsIncomplete() throws {
        let yaml = """
        PODS:
          - ExternalKit (1.0.0)
        DEPENDENCIES:
          - ExternalKit
        EXTERNAL SOURCES:
          ExternalKit:
            :tag: 1.0.0
            :git: https://example.invalid/Owner/ExternalKit.git
        CHECKOUT OPTIONS:
          ExternalKit:
            :commit: abcdef123456
            :git: https://example.invalid/Owner/ExternalKit.git
        """

        let dependency = try #require(PodfileLockParser().parse(content: yaml).first)
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected Git lockfile provenance")
            return
        }
        #expect(provenance.status == .incomplete)
        #expect(provenance.lockfile?.checkoutReference?.isFullCheckoutCommit == false)
    }
}
