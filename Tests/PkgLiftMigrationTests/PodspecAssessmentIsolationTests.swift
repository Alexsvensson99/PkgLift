import Foundation
import PkgLiftCocoaPods
import PkgLiftCore
import XCTest
@testable import PkgLiftMigration

final class PodspecAssessmentIsolationTests: XCTestCase {
    func testExistingPlannerContractRemainsStableAlongsideAssessment() throws {
        let dependency = CocoaPodDependency(
            name: "Alamofire",
            version: "5.0.0",
            source: .registry,
            isDirect: true,
            targets: ["App"],
            declarations: [
                PodfileDeclaration(
                    line: 1,
                    scope: .target,
                    scopeName: "App",
                    targetName: "App",
                    source: .registry
                ),
            ],
            targetAttribution: TargetAttribution(status: .exact, targets: ["App"])
        )
        let mapping = RegistryMapping(
            pod: PodIdentifier(name: "Alamofire"),
            swiftpm: SwiftPMPackageInfo(
                repository: "https://github.com/Alamofire/Alamofire",
                products: ["Alamofire"],
                minimumVersion: "5.0.0",
                supportedConsumerLanguages: [.swift]
            ),
            migration: MigrationInfo(confidence: .verified)
        )
        let target = TargetInfo(
            name: "App",
            type: "application",
            sourceProfile: TargetSourceProfile(
                languages: [.swift],
                completeness: .complete
            )
        )

        let inspection = try PodspecJSONInspector().inspect(json: Data(#"""
        {
          "name": "Alamofire",
          "version": "5.0.0",
          "compiler_flags": ["-DUNSUPPORTED_FOR_ASSESSMENT"]
        }
        """#.utf8))
        let assessment = try PodspecSwiftPMAssessor().assess(
            inspection,
            cocoaPodsProfile: .cocoaPodsCore1_17_0,
            swiftPMProfile: .swiftToolsVersion6_0
        )
        XCTAssertEqual(assessment.outcome, .unsupported)

        let entry = MigrationPlanner().generatePlan(
            dependencies: ["Alamofire": dependency],
            mappings: ["Alamofire": mapping],
            availableTargets: ["App"],
            availableTargetInfos: [target]
        ).entries[0]

        XCTAssertEqual(entry.classification, .auto)
        XCTAssertEqual(entry.actions, [
            .removePod(name: "Alamofire"),
            .addSwiftPackage(
                repositoryURL: "https://github.com/Alamofire/Alamofire",
                requirement: .exact("5.0.0")
            ),
            .linkProduct(
                repositoryURL: "https://github.com/Alamofire/Alamofire",
                productName: "Alamofire",
                targetName: "App"
            ),
        ])
        XCTAssertEqual(entry.targetName, "App")
        XCTAssertEqual(entry.targetSourceProfile, target.sourceProfile)
    }

    func testAssessmentSymbolsRemainOutsideProductionMigrationSurfaces() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = repositoryRoot.appendingPathComponent("Sources", isDirectory: true)
        let assessmentSource = sourcesRoot.appendingPathComponent(
            "PkgLiftCocoaPods/PodspecSwiftPMAssessment.swift",
            isDirectory: false
        )
        let forbiddenSymbols = [
            "PodspecSwiftPMAssessment",
            "PodspecSwiftPMAssessmentReason",
            "PodspecSwiftPMAssessor",
            "SwiftPMCapabilityProfile",
        ]

        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourcesRoot,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        for case let fileURL as URL in enumerator
        where fileURL.pathExtension == "swift"
            && fileURL.standardizedFileURL != assessmentSource.standardizedFileURL {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for symbol in forbiddenSymbols {
                XCTAssertFalse(
                    contents.contains(symbol),
                    "\(symbol) crossed the analysis-only boundary into \(fileURL.path)"
                )
            }
        }
    }
}
