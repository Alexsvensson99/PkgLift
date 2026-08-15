import Foundation
import XCTest
import PkgLiftCore
@testable import PkgLiftMigration

final class MigrationEngineTests: XCTestCase {
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
