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
        guard case .git(let provenance)? = external.sourceProvenance else {
            Issue.record("Expected reconciled Git provenance")
            return
        }
        #expect(provenance.status == .ambiguousRepository)
        #expect(provenance.declarations.count == 1)
        #expect(provenance.lockfile != nil)
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

    @Test("Reconcile a tag declaration and full checkout as immutable evidence")
    func testMapperReconcilesTagAndCheckoutAsSupportedImmutable() throws {
        let commit = String(repeating: "a", count: 40)
        let podfile = """
        target 'App' do
          pod 'ExternalKit', git: 'https://example.invalid/Owner/ExternalKit.git', tag: '1.0.0'
        end
        """
        let lockfile = """
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
            :commit: \(commit)
            :git: https://example.invalid/Owner/ExternalKit.git
        """

        let dependency = try #require(PodfileTargetMapper().map(
            podfileContent: podfile,
            lockfileDependencies: PodfileLockParser().parse(content: lockfile)
        ).first)
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected reconciled Git provenance")
            return
        }
        #expect(provenance.status == .supportedImmutable)
        #expect(dependency.source == .git(
            url: "https://example.invalid/Owner/ExternalKit",
            ref: .tag("1.0.0")
        ))
        #expect(dependency.hasLiteralMigrationProvenance == false)
    }

    @Test("Keep a branch mutable when lockfile also records a checkout commit")
    func testMapperKeepsBranchMutable() throws {
        let commit = String(repeating: "b", count: 40)
        let podfile = """
        target 'App' do
          pod 'ExternalKit', git: 'https://example.invalid/Owner/ExternalKit.git', branch: 'main'
        end
        """
        let lockfile = """
        PODS:
          - ExternalKit (1.0.0)
        DEPENDENCIES:
          - ExternalKit
        EXTERNAL SOURCES:
          ExternalKit:
            :branch: main
            :git: https://example.invalid/Owner/ExternalKit.git
        CHECKOUT OPTIONS:
          ExternalKit:
            :commit: \(commit)
            :git: https://example.invalid/Owner/ExternalKit.git
        """

        let dependency = try #require(PodfileTargetMapper().map(
            podfileContent: podfile,
            lockfileDependencies: PodfileLockParser().parse(content: lockfile)
        ).first)
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected reconciled Git provenance")
            return
        }
        #expect(provenance.status == .mutable)
    }

    @Test("Do not choose between conflicting declaration and lock repositories")
    func testMapperMarksRepositoryMismatchConflicting() throws {
        let commit = String(repeating: "c", count: 40)
        let podfile = """
        target 'App' do
          pod 'ExternalKit', git: 'https://example.invalid/Owner/Declared.git', tag: '1.0.0'
        end
        """
        let lockfile = """
        PODS:
          - ExternalKit (1.0.0)
        DEPENDENCIES:
          - ExternalKit
        EXTERNAL SOURCES:
          ExternalKit:
            :tag: 1.0.0
            :git: https://example.invalid/Owner/Locked.git
        CHECKOUT OPTIONS:
          ExternalKit:
            :commit: \(commit)
            :git: https://example.invalid/Owner/Locked.git
        """

        let dependency = try #require(PodfileTargetMapper().map(
            podfileContent: podfile,
            lockfileDependencies: PodfileLockParser().parse(content: lockfile)
        ).first)
        #expect(dependency.source == .unknown)
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected conflicting Git provenance")
            return
        }
        #expect(provenance.status == .conflicting)
    }

    @Test("Mixed registry and Git declarations remain conflicting")
    func testMixedRegistryAndGitDeclarationsRemainConflicting() throws {
        let commit = String(repeating: "d", count: 40)
        let repositoryURL = "https://example.invalid/Owner/ExternalKit"
        let podfile = """
        target 'App' do
          pod 'ExternalKit'
          pod 'ExternalKit', git: '\(repositoryURL).git', tag: '1.0.0'
        end
        """
        let lockfile = """
        PODS:
          - ExternalKit (1.0.0)
        DEPENDENCIES:
          - ExternalKit
        EXTERNAL SOURCES:
          ExternalKit:
            :tag: 1.0.0
            :git: \(repositoryURL).git
        CHECKOUT OPTIONS:
          ExternalKit:
            :commit: \(commit)
            :git: \(repositoryURL).git
        """

        let dependency = try #require(PodfileTargetMapper().map(
            podfileContent: podfile,
            lockfileDependencies: PodfileLockParser().parse(content: lockfile)
        ).first)

        #expect(dependency.source == .unknown)
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected conflicting Git provenance")
            return
        }
        #expect(provenance.status == .conflicting)
        let origins = try #require(dependency.declarations)
        #expect(origins.count == 2)
        #expect(origins.contains { $0.source == .registry })
        #expect(origins.contains {
            $0.source == .git(url: repositoryURL, ref: .tag("1.0.0"))
        })
    }

    @Test("Registry declaration conflicts with an external Git lockfile")
    func testRegistryDeclarationConflictsWithExternalGitLockfile() throws {
        let commit = String(repeating: "e", count: 40)
        let podfile = """
        target 'App' do
          pod 'ExternalKit'
        end
        """
        let lockfile = """
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
            :commit: \(commit)
            :git: https://example.invalid/Owner/ExternalKit.git
        """

        let dependency = try #require(PodfileTargetMapper().map(
            podfileContent: podfile,
            lockfileDependencies: PodfileLockParser().parse(content: lockfile)
        ).first)

        #expect(dependency.source == .unknown)
        guard case .git(let provenance)? = dependency.sourceProvenance else {
            Issue.record("Expected conflicting Git provenance")
            return
        }
        #expect(provenance.status == .conflicting)
        #expect(provenance.lockfile?.hasConflictingEvidence == true)
        #expect(dependency.declarations?.first?.source == .registry)
    }

    @Test("Preserve unmatched lockfile provenance")
    func testUnmatchedLockDependencyPreservesProvenance() throws {
        let lockfile = """
        PODS:
          - ExternalKit (1.0.0)
        EXTERNAL SOURCES:
          ExternalKit:
            :branch: main
            :git: https://example.invalid/Owner/ExternalKit.git
        """
        let lockDependencies = try PodfileLockParser().parse(content: lockfile)

        let dependency = try #require(PodfileTargetMapper().mapLockfileDependencies(
            lockDependencies,
            declarations: []
        ).first)
        #expect(dependency.sourceProvenance == lockDependencies.first?.sourceProvenance)
    }
}
