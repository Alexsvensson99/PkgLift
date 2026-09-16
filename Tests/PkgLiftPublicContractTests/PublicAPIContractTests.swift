import Foundation
import XCTest
import PkgLiftCore
import PkgLiftCocoaPods
import PkgLiftXcode
import PkgLiftRegistry
import PkgLiftMigration
import PkgLiftVerification

/// These client examples intentionally have no @testable imports.
final class PublicAPIContractTests: XCTestCase {
    func testPublicParserRegistryAndPlannerPreserveUnmappedDependency() async throws {
        let parsed = PodfileParser().parse(content: """
        target 'App' do
          pod 'UnmappedContractExample', '1.0.0'
        end
        """)
        let dependency = try XCTUnwrap(parsed.directDependencies.first)
        XCTAssertEqual(parsed.targets, ["App"])

        let registry = RegistryLoader()
        try await registry.load()
        let mapping = await registry.lookup(name: dependency.name)
        XCTAssertNil(mapping)
        let cryptoSwift = await registry.lookup(name: "CryptoSwift")
        let verifiedMapping = try XCTUnwrap(cryptoSwift)
        XCTAssertTrue(RegistryValidator().validate(verifiedMapping, filePath: "bundled/CryptoSwift.yml").isEmpty)

        let plan: PkgLiftCore.MigrationPlan = MigrationPlanner().generatePlan(
            dependencies: [dependency.name: dependency],
            mappings: [:],
            projectPath: "/example/App.xcodeproj",
            podfileFeatures: parsed.features,
            availableTargets: parsed.targets
        )
        XCTAssertTrue(plan.autoEntries.isEmpty)
        XCTAssertEqual(plan.unknownEntries.map(\.podName), [dependency.name])
        XCTAssertFalse(plan.entries.flatMap(\.actions).contains { action in
            if case .removePod = action { return true }
            return false
        })
    }

    func testPublicWorkspaceAndBuildOptionsRejectUnsafeInputs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftPublicContract-\(UUID().uuidString)")
        let workspace = root.appendingPathComponent("App.xcworkspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <Workspace version="1.0">
          <FileRef location="group:../Outside.xcodeproj"/>
        </Workspace>
        """.write(to: workspace.appendingPathComponent("contents.xcworkspacedata"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try WorkspaceAnalyzer().analyzeWorkspace(at: workspace.path, containedIn: root.path)) { error in
            guard case WorkspaceAnalyzerError.projectReferenceOutsideRoot = error else {
                return XCTFail("Expected a typed containment refusal, got \(error)")
            }
        }
        XCTAssertThrowsError(try BuildVerificationOptions(configuration: "Debug\nRelease").validated()) { error in
            XCTAssertEqual(error as? BuildVerificationOptionsError, .controlCharacter(field: "configuration"))
        }
        let settings = try BuildVerificationOptions(configuration: " Debug ", derivedDataPath: "/private/client/DerivedData").validated()
        XCTAssertEqual(settings.configuration, "Debug")
        XCTAssertFalse(settings.redactedSummary.contains("/private/client"))
    }
}
