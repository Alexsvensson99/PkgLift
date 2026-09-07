import Foundation
import XCTest
import PkgLiftCore
@testable import PkgLiftMigration

final class MigrationEngineTests: XCTestCase {
    func testFailedPodfilePostconditionRestoresBothOriginals() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let podfile = root.appendingPathComponent("Podfile")
        let project = root.appendingPathComponent("App.xcodeproj")
        let projectFile = project.appendingPathComponent("project.pbxproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let original = "target 'App' do\n  pod 'Alamofire'\nend\n"
        try original.write(to: podfile, atomically: true, encoding: .utf8)
        try Data("original project".utf8).write(to: projectFile)
        XCTAssertThrowsError(try MigrationEngine().execute(
            prepared: PreparedMigration(podsToRemove: ["Alamofire"], packagesToAdd: [], productsToLink: []),
            podfileURL: podfile,
            projectPath: project.path,
            backupDir: root.appendingPathComponent("backup"),
            checkpoint: { stage in
                if stage == .podfileWritten {
                    try "target 'App' do\n  pod('Alamofire')\nend\n".write(
                        to: podfile, atomically: true, encoding: .utf8
                    )
                    try Data("changed project".utf8).write(to: projectFile)
                }
            }
        )) { error in
            guard case AtomicMigration.MigrationError.actionFailed(let underlying) = error else {
                return XCTFail("Expected rollback, got \(error)")
            }
            XCTAssertEqual(underlying as? MigrationEngineError, .podRemovalNotVerified)
        }
        XCTAssertEqual(try String(contentsOf: podfile, encoding: .utf8), original)
        XCTAssertEqual(try Data(contentsOf: projectFile), Data("original project".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-in-progress").path))
    }

    func testLegacyApplyWithoutProjectContextIsRefusedBeforePodfileMutation() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let podfile = root.appendingPathComponent("Podfile")
        let planURL = root.appendingPathComponent("plan.json")
        let original = "target 'App' do\n  pod 'Alamofire'\nend"
        try original.write(to: podfile, atomically: true, encoding: .utf8)
        try writePlan(makePlan(), to: planURL)

        XCTAssertThrowsError(try MigrationEngine().execute(
            planURL: planURL,
            podfileURL: podfile,
            isDryRun: false
        )) { error in
            XCTAssertEqual(error as? MigrationEngineError, .projectContextRequired)
        }
        XCTAssertEqual(try String(contentsOf: podfile), original)
    }

    func testMissingExactPodDeclarationRefusesBeforeAnyMutation() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let podfile = root.appendingPathComponent("Podfile")
        let project = root.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let original = "target 'App' do\n  pod 'SnapKit'\nend"
        try original.write(to: podfile, atomically: true, encoding: .utf8)
        let projectMarker = project.appendingPathComponent("marker")
        try "unchanged".write(to: projectMarker, atomically: true, encoding: .utf8)
        let prepared = PreparedMigration(
            podsToRemove: ["Alamofire"],
            packagesToAdd: [],
            productsToLink: []
        )

        XCTAssertThrowsError(try MigrationEngine().execute(
            prepared: prepared,
            podfileURL: podfile,
            projectPath: project.path,
            backupDir: root.appendingPathComponent("backup")
        )) { error in
            XCTAssertEqual(
                error as? MigrationEngineError,
                .missingPodDeclarations(["Alamofire"])
            )
        }
        XCTAssertEqual(try String(contentsOf: podfile), original)
        XCTAssertEqual(try String(contentsOf: projectMarker), "unchanged")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("backup").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-in-progress").path))
    }

    func testCancellationBeforeMutationCreatesNoRecoveryState() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let podfile = root.appendingPathComponent("Podfile")
        let content = "target 'App' do\n  pod 'Alamofire'\nend\n"
        try content.write(to: podfile, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try MigrationEngine().execute(
            prepared: PreparedMigration(podsToRemove: ["Alamofire"], packagesToAdd: [], productsToLink: []),
            podfileURL: podfile,
            projectPath: root.appendingPathComponent("App.xcodeproj").path,
            backupDir: root.appendingPathComponent("backup"),
            checkCancellation: { throw CancellationError() }
        )) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try String(contentsOf: podfile, encoding: .utf8), content)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("backup").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-in-progress").path))
    }

    func testXcodeEditErrorAfterPodfileWriteRestoresBothOriginals() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let podfile = root.appendingPathComponent("Podfile")
        let project = root.appendingPathComponent("App.xcodeproj")
        let pbxproj = project.appendingPathComponent("project.pbxproj")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let originalPodfile = Data("target 'App' do\n  pod 'Alamofire'\nend\n".utf8)
        let originalProject = Data("invalid project causes a real Xcode editor error".utf8)
        try originalPodfile.write(to: podfile)
        try originalProject.write(to: pbxproj)
        let prepared = PreparedMigration(
            podsToRemove: ["Alamofire"],
            packagesToAdd: [.init(repositoryURL: "https://github.com/Alamofire/Alamofire", requirement: .exact("5.0.0"))],
            productsToLink: []
        )
        var observedPodfileWrite = false
        XCTAssertThrowsError(try MigrationEngine().execute(
            prepared: prepared,
            podfileURL: podfile,
            projectPath: project.path,
            backupDir: root.appendingPathComponent("backup"),
            checkpoint: { stage in
                if stage == .podfileWritten {
                    observedPodfileWrite = true
                    XCTAssertNotEqual(try Data(contentsOf: podfile), originalPodfile)
                }
            }
        )) { error in
            guard case AtomicMigration.MigrationError.actionFailed(let underlying) = error else {
                return XCTFail("Expected original editor error after rollback: \(error)")
            }
            XCTAssertFalse(underlying is CancellationError)
        }
        XCTAssertTrue(observedPodfileWrite)
        XCTAssertEqual(try Data(contentsOf: podfile), originalPodfile)
        XCTAssertEqual(try Data(contentsOf: pbxproj), originalProject)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-in-progress").path))
    }

    func testExistingRecoveryStateIsRefusedBeforeReadingPartialPodfile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("migration-in-progress")
        let markerData = Data("interrupted marker".utf8)
        try markerData.write(to: marker)
        let backup = root.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        let original = Data("known-good Podfile".utf8)
        try original.write(to: backup.appendingPathComponent("Podfile"))
        for _ in 0..<2 {
            XCTAssertThrowsError(try MigrationEngine().execute(
                prepared: PreparedMigration(podsToRemove: [], packagesToAdd: [], productsToLink: []),
                podfileURL: root.appendingPathComponent("missing-Podfile"),
                projectPath: root.appendingPathComponent("missing.xcodeproj").path,
                backupDir: backup
            )) { XCTAssertTrue($0.localizedDescription.lowercased().contains("incomplete")) }
            XCTAssertEqual(try Data(contentsOf: marker), markerData)
            XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Podfile")), original)
        }
    }

    private func makePlan() -> MigrationPlan {
        let package = PackageCandidate(
            repositoryURL: "https://github.com/Alamofire/Alamofire",
            products: ["Alamofire"],
            versionRequirement: .exact("5.0.0"),
            confidence: .verified
        )
        let entry = MigrationPlanEntry(
            podName: "Alamofire",
            currentVersion: "5.0.0",
            classification: .auto,
            actions: [
                .removePod(name: "Alamofire"),
                .addSwiftPackage(repositoryURL: package.repositoryURL, requirement: .exact("5.0.0")),
                .linkProduct(
                    repositoryURL: package.repositoryURL,
                    productName: "Alamofire",
                    targetName: "App"
                ),
            ],
            targetName: "App",
            packageCandidate: package
        )
        return MigrationPlan(projectPath: "/tmp/App.xcodeproj", entries: [entry], issues: [], readinessScore: 100)
    }

    private func writePlan(_ plan: MigrationPlan, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(plan).write(to: url)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftEngine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
