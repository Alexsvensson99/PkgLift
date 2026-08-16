import Foundation
import XCTest
@testable import PkgLiftCore

final class DiagnosticsReportTests: XCTestCase {
    func testReportContainsCountsButOmitsProjectIdentifiersAndURLs() throws {
        let secretPath = "/Users/alex/Secret Client/App.xcodeproj"
        let secretWorkspace = "/Users/alex/Secret Client/App.xcworkspace"
        let secretPod = "InternalAnalyticsCanary"
        let secretTarget = "CustomerProductionTarget"
        let secretURL = "https://token@example.invalid/private/repository.git"
        let secretMessage = "sk-proj-CANARYSECRET0123456789"

        var features = PodfileFeatures()
        features.hasPostInstallHook = true
        features.hasDynamicRuby = true
        features.integrationMarkers = [.reactNative]

        let pod = CocoaPodDependency(
            name: secretPod,
            version: "1.2.3",
            source: .git(url: secretURL, ref: .branch("private")),
            isDirect: true,
            targets: [secretTarget]
        )
        let issue = MigrationIssue(
            severity: .warning,
            message: secretMessage,
            detail: "developer@example.invalid",
            dependency: secretPod
        )
        let candidate = MigrationCandidate(
            pod: pod,
            classification: .review,
            packageCandidate: PackageCandidate(
                repositoryURL: secretURL,
                products: [secretTarget],
                versionRequirement: .exact("1.2.3")
            ),
            reasons: [secretMessage],
            issues: [issue]
        )
        let analysis = ProjectAnalysis(
            project: ProjectInfo(
                projectPath: secretPath,
                workspacePath: secretWorkspace,
                targets: [
                    TargetInfo(
                        name: secretTarget,
                        type: "application",
                        platform: "iOS",
                        deploymentTarget: "17.0"
                    )
                ]
            ),
            cocoaPods: CocoaPodsState(
                directDependencies: [pod, pod],
                transitiveDependencies: [],
                hasPodfile: true,
                hasPodfileLock: true,
                hasManifestLock: false,
                podfileFeatures: features
            ),
            swiftPM: SwiftPMState(
                packages: [
                    SwiftPMDependency(
                        repositoryURL: secretURL,
                        requirement: .exact("1.2.3"),
                        linkedProducts: [
                            LinkedProduct(productName: secretTarget, targetName: secretTarget)
                        ]
                    )
                ],
                hasPackageResolved: true
            ),
            candidates: [candidate],
            issues: [issue],
            readinessScore: 42,
            counts: DependencyCounts(
                literalPodfileDeclarationCount: 2,
                uniqueDirectDependencyCount: 1,
                uniqueLockfileDependencyCount: 1,
                planEntryCount: 1,
                analysisCandidateCount: 1
            ),
            detectedIntegrations: [.reactNative, .carthage]
        )
        let discovery = DiscoveredFiles(
            rootPath: "/Users/alex/Secret Client",
            podfilePath: "/Users/alex/Secret Client/Podfile",
            podfileLockPath: "/Users/alex/Secret Client/Podfile.lock",
            manifestLockPath: nil,
            projectPaths: [secretPath],
            workspacePaths: [secretWorkspace],
            configPath: nil,
            localRegistryPath: nil,
            hasCartfile: true
        )

        let report = DiagnosticsReportBuilder().build(
            environment: DiagnosticsEnvironmentSummary(
                macOS: "macOS 15.6",
                xcode: "Xcode 16.4",
                swift: "Swift 6.1",
                cocoaPods: "1.16.2"
            ),
            discovery: discovery,
            analysis: analysis,
            git: DiagnosticsGitSummary(state: .dirty, changedFileCount: 2),
            failures: []
        )

        let data = try DiagnosticsReportWriter().encode(report)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        [
            secretPath,
            secretWorkspace,
            secretPod,
            secretTarget,
            secretURL,
            secretMessage,
            "developer@example.invalid",
            "/Users/alex",
        ].forEach { secret in
            XCTAssertFalse(json.contains(secret), "Report leaked \(secret)")
        }

        XCTAssertEqual(report.status, .complete)
        XCTAssertEqual(report.project.root, "<PROJECT_ROOT>")
        XCTAssertEqual(report.project.discoveredProjectCount, 1)
        XCTAssertEqual(report.project.discoveredWorkspaceCount, 1)
        XCTAssertEqual(report.project.targetCount, 1)
        XCTAssertEqual(report.project.integrations, [.carthage, .reactNative])
        XCTAssertEqual(report.project.integrationCount, 2)
        XCTAssertEqual(report.cocoaPods.directDependencyCount, 1)
        XCTAssertEqual(report.swiftPM?.existingPackageCount, 1)
        XCTAssertEqual(report.classifications?.review, 1)
        XCTAssertEqual(report.issues?.warning, 1)
        XCTAssertTrue(report.privacy.redactionEnabled)
        XCTAssertFalse(report.privacy.automaticUpload)
        XCTAssertFalse(json.contains("Cartfile"))
        XCTAssertFalse(json.contains("use_react_native!"))
    }

    func testEncodingIsDeterministic() throws {
        let report = DiagnosticsReportBuilder().build(
            environment: DiagnosticsEnvironmentSummary(
                macOS: "macOS",
                xcode: nil,
                swift: nil,
                cocoaPods: nil
            ),
            discovery: nil,
            analysis: nil,
            git: .unknown,
            failures: [DiagnosticsFailure(stage: .discovery, type: "Example.Error")]
        )
        let writer = DiagnosticsReportWriter()

        XCTAssertEqual(try writer.encode(report), try writer.encode(report))
        XCTAssertEqual(report.status, .partial)
    }

    func testWriterUsesPrivatePermissionsAndRequiresExplicitOverwrite() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftDiagnostics-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("nested/report.json")
        let report = makePartialReport()
        let writer = DiagnosticsReportWriter()

        try writer.write(report, to: output, overwrite: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)

        XCTAssertThrowsError(try writer.write(report, to: output, overwrite: false)) { error in
            guard case DiagnosticsReportWriterError.outputExists = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertNoThrow(try writer.write(report, to: output, overwrite: true))
    }

    func testWriterRejectsDanglingSymbolicLinkEvenWithOverwrite() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftDiagnosticsSymlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let missingTarget = root.appendingPathComponent("missing-target.json")
        let output = root.appendingPathComponent("report.json")
        try FileManager.default.createSymbolicLink(
            atPath: output.path,
            withDestinationPath: missingTarget.path
        )

        XCTAssertThrowsError(
            try DiagnosticsReportWriter().write(
                makePartialReport(),
                to: output,
                overwrite: true
            )
        ) { error in
            guard case DiagnosticsReportWriterError.outputIsSymbolicLink = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: output.path),
            missingTarget.path
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingTarget.path))
    }

    private func makePartialReport() -> DiagnosticsReport {
        DiagnosticsReportBuilder().build(
            environment: DiagnosticsEnvironmentSummary(
                macOS: "macOS",
                xcode: nil,
                swift: nil,
                cocoaPods: nil
            ),
            discovery: nil,
            analysis: nil,
            git: .unknown,
            failures: [DiagnosticsFailure(stage: .analysis, type: "Example.Error")]
        )
    }
}
