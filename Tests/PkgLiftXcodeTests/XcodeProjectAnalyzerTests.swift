import Foundation
import PathKit
import XCTest
import XcodeProj
import PkgLiftCore
@testable import PkgLiftXcode

final class XcodeProjectAnalyzerTests: XCTestCase {
    func testReadsDirectTargetDeploymentSettings() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "iphoneos",
                    "IPHONEOS_DEPLOYMENT_TARGET": "15.0",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)

        XCTAssertEqual(target.platform, "iOS")
        XCTAssertEqual(target.deploymentTarget, "15.0")
    }

    func testUsesDeploymentSignalWhenSDKRootIsAuto() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "auto",
                    "MACOSX_DEPLOYMENT_TARGET": "14.0",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertEqual(target.platform, "macOS")
        XCTAssertEqual(target.deploymentTarget, "14.0")
    }

    func testAutoSDKRootWithoutDeploymentSignalLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: ["Debug": ["SDKROOT": "auto"]]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testRecognizesVisionSimulatorSDKRoot() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "xrsimulator",
                    "XROS_DEPLOYMENT_TARGET": "2.0",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertEqual(target.platform, "visionOS")
        XCTAssertEqual(target.deploymentTarget, "2.0")
    }

    func testReadsTargetAndProjectBaseXcconfigsWithIncludes() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write("#include \"Shared/Platform.xcconfig\"\n", to: root.appendingPathComponent("Configs/Project.xcconfig"))
        try write("SDKROOT = macosx\n", to: root.appendingPathComponent("Configs/Shared/Platform.xcconfig"))
        try write("#include \"Shared/TargetVersion.xcconfig\"\n", to: root.appendingPathComponent("Configs/Target.xcconfig"))
        try write("MACOSX_DEPLOYMENT_TARGET = 12.0\n", to: root.appendingPathComponent("Configs/Shared/TargetVersion.xcconfig"))

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug", "Release"],
            projectSettings: [
                "Debug": ["MACOSX_DEPLOYMENT_TARGET": "13.0"],
                "Release": ["MACOSX_DEPLOYMENT_TARGET": "13.0"],
            ],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Project.xcconfig",
            targetBaseConfigurationPath: "Configs/Target.xcconfig"
        )

        let target = try analyzedTarget(in: project)

        XCTAssertEqual(target.platform, "macOS")
        XCTAssertEqual(target.deploymentTarget, "12.0")
    }

    func testLocalXCConfigSettingOverridesOptionalIncludeWhetherPresentOrMissing() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "SDKROOT = macosx\nMACOSX_DEPLOYMENT_TARGET = 13.0\n#include? \"Downstream.xcconfig\"\n",
            to: root.appendingPathComponent("Configs/Project.xcconfig")
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Project.xcconfig"
        )

        var target = try analyzedTarget(in: project)
        XCTAssertEqual(target.platform, "macOS")
        XCTAssertEqual(target.deploymentTarget, "13.0")

        try write(
            "MACOSX_DEPLOYMENT_TARGET = 14.0\n",
            to: root.appendingPathComponent("Configs/Downstream.xcconfig")
        )
        target = try analyzedTarget(in: project)
        XCTAssertEqual(target.platform, "macOS")
        XCTAssertEqual(target.deploymentTarget, "13.0")
    }

    func testLaterIncludeOverridesEarlierIncludeBeforeLocalSettings() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "#include \"First.xcconfig\"\n#include \"Second.xcconfig\"\nSDKROOT = macosx\n",
            to: root.appendingPathComponent("Configs/Project.xcconfig")
        )
        try write(
            "MACOSX_DEPLOYMENT_TARGET = 12.0\n",
            to: root.appendingPathComponent("Configs/First.xcconfig")
        )
        try write(
            "MACOSX_DEPLOYMENT_TARGET = 14.0\n",
            to: root.appendingPathComponent("Configs/Second.xcconfig")
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Project.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertEqual(target.platform, "macOS")
        XCTAssertEqual(target.deploymentTarget, "14.0")
    }

    func testAppliesProjectAndTargetConfigurationPrecedence() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "SDKROOT = macosx\nMACOSX_DEPLOYMENT_TARGET = 10.0\n",
            to: root.appendingPathComponent("Configs/Project.xcconfig")
        )
        try write(
            "MACOSX_DEPLOYMENT_TARGET = 12.0\n",
            to: root.appendingPathComponent("Configs/Target.xcconfig")
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: ["Debug": ["MACOSX_DEPLOYMENT_TARGET": "11.0"]],
            targetSettings: ["Debug": ["MACOSX_DEPLOYMENT_TARGET": "13.0"]],
            projectBaseConfigurationPath: "Configs/Project.xcconfig",
            targetBaseConfigurationPath: "Configs/Target.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertEqual(target.platform, "macOS")
        XCTAssertEqual(target.deploymentTarget, "13.0")
    }

    func testMissingRequiredIncludeLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "#include \"Missing.xcconfig\"\nSDKROOT = macosx\nMACOSX_DEPLOYMENT_TARGET = 13.0\n",
            to: root.appendingPathComponent("Configs/Project.xcconfig")
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Project.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testConditionalRelevantXCConfigSettingLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "SDKROOT = macosx\nMACOSX_DEPLOYMENT_TARGET[sdk=macosx*] = 13.0\n",
            to: root.appendingPathComponent("Configs/Project.xcconfig")
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Project.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testConditionalProjectBuildSettingLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [
                "Debug": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "12.0",
                    "MACOSX_DEPLOYMENT_TARGET[sdk=macosx*]": "13.0",
                ],
            ],
            targetSettings: [:]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testConditionalTargetBuildSettingLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "12.0",
                    "MACOSX_DEPLOYMENT_TARGET[sdk=macosx*]": "13.0",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testMacroBasedDirectSettingLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "$(MINIMUM_OS_VERSION)",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testBlockCommentSyntaxInDirectSettingLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "13.0 /* unsupported */",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testMacroBasedXCConfigSettingLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "SDKROOT = macosx\nMACOSX_DEPLOYMENT_TARGET = $(MINIMUM_OS_VERSION)\n",
            to: root.appendingPathComponent("Configs/Project.xcconfig")
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Project.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testRelevantBlockCommentSyntaxLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "SDKROOT = macosx /* unsupported */\nMACOSX_DEPLOYMENT_TARGET = 13.0\n",
            to: root.appendingPathComponent("Configs/Project.xcconfig")
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Project.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testIncludeCycleLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "#include \"B.xcconfig\"\nSDKROOT = macosx\n",
            to: root.appendingPathComponent("Configs/A.xcconfig")
        )
        try write(
            "#include \"A.xcconfig\"\nMACOSX_DEPLOYMENT_TARGET = 13.0\n",
            to: root.appendingPathComponent("Configs/B.xcconfig")
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/A.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testInvalidUTF8BaseConfigurationLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let config = root.appendingPathComponent("Configs/Project.xcconfig")
        try FileManager.default.createDirectory(
            at: config.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xFF]).write(to: config)
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Project.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testAbsoluteBaseConfigurationOutsideContainmentLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        let externalRoot = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: externalRoot)
        }

        let externalConfig = externalRoot.appendingPathComponent("External.xcconfig")
        try write(
            "SDKROOT = macosx\nMACOSX_DEPLOYMENT_TARGET = 13.0\n",
            to: externalConfig
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: externalConfig.path
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testExplicitContainmentRootAllowsSiblingBaseConfiguration() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "SDKROOT = macosx\nMACOSX_DEPLOYMENT_TARGET = 13.0\n",
            to: root.appendingPathComponent("Configs/Shared.xcconfig")
        )
        let project = try writeProject(
            in: root.appendingPathComponent("App"),
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "../Configs/Shared.xcconfig"
        )

        let result = try XcodeProjectAnalyzer().analyzeProject(
            at: project.path,
            containedIn: root.path
        )
        let target = try XCTUnwrap(result.targets.first(where: { $0.name == "Example" }))
        XCTAssertEqual(target.platform, "macOS")
        XCTAssertEqual(target.deploymentTarget, "13.0")
    }

    func testXCConfigSymlinkOutsideContainmentLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        let externalRoot = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: externalRoot)
        }

        let externalConfig = externalRoot.appendingPathComponent("External.xcconfig")
        try write(
            "SDKROOT = macosx\nMACOSX_DEPLOYMENT_TARGET = 13.0\n",
            to: externalConfig
        )
        let linkedConfig = root.appendingPathComponent("Configs/Linked.xcconfig")
        try FileManager.default.createDirectory(
            at: linkedConfig.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedConfig,
            withDestinationURL: externalConfig
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Linked.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testOversizedBaseConfigurationLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let contents = "SDKROOT = macosx\nMACOSX_DEPLOYMENT_TARGET = 13.0\nOTHER = "
            + String(repeating: "x", count: 1_048_576)
        try write(contents, to: root.appendingPathComponent("Configs/Project.xcconfig"))
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Project.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testRelativeIncludeDoesNotFallBackToProjectRoot() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "#include \"OnlyAtProjectRoot.xcconfig\"\nSDKROOT = macosx\n",
            to: root.appendingPathComponent("Configs/Nested/Project.xcconfig")
        )
        try write(
            "MACOSX_DEPLOYMENT_TARGET = 13.0\n",
            to: root.appendingPathComponent("OnlyAtProjectRoot.xcconfig")
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Nested/Project.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testUnrelatedRecursivePathGlobIsNotParsedAsBlockComment() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            "SDKROOT = macosx\nMACOSX_DEPLOYMENT_TARGET = 13.0\nHEADER_SEARCH_PATHS = $(SRCROOT)/Pods/**\n",
            to: root.appendingPathComponent("Configs/Project.xcconfig")
        )
        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:],
            projectBaseConfigurationPath: "Configs/Project.xcconfig"
        )

        let target = try analyzedTarget(in: project)
        XCTAssertEqual(target.platform, "macOS")
        XCTAssertEqual(target.deploymentTarget, "13.0")
    }

    func testLeavesEnvironmentUnsetWhenConfigurationsDisagree() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug", "Release"],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "13.0",
                ],
                "Release": [
                    "SDKROOT": "iphoneos",
                    "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)

        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testLeavesEnvironmentUnsetWhenDeploymentVersionsDisagree() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug", "Release"],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "13.0",
                ],
                "Release": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "14.0",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testLeavesEnvironmentUnsetForMultiplePlatformSignals() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "macosx",
                    "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testLeavesEnvironmentUnsetWhenProjectConfigurationIsMissing() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectConfigurationNames: ["Release"],
            projectSettings: [
                "Release": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "13.0",
                ],
            ],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "13.0",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testLeavesEnvironmentUnsetWhenProjectConfigurationListIsEmpty() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectConfigurationNames: [],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "13.0",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testMalformedSDKVersionSuffixLeavesEnvironmentUnset() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [
                "Debug": [
                    "SDKROOT": "macosx1..2",
                    "MACOSX_DEPLOYMENT_TARGET": "13.0",
                ],
            ]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testLeavesEnvironmentUnsetWhenProjectConfigurationIsDuplicated() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectConfigurationNames: ["Debug", "Debug"],
            projectSettings: [
                "Debug": [
                    "SDKROOT": "macosx",
                    "MACOSX_DEPLOYMENT_TARGET": "13.0",
                ],
            ],
            targetSettings: [:]
        )

        let target = try analyzedTarget(in: project)
        XCTAssertNil(target.platform)
        XCTAssertNil(target.deploymentTarget)
    }

    func testSortsSwiftPMPackagesAndLinkedProductsDeterministically() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeSwiftPackageProject(in: root)
        let result = try XcodeProjectAnalyzer().analyzeProject(at: project.path)
        let packages = result.swiftPMState.packages

        XCTAssertEqual(result.targets.map(\.name), ["Alpha", "Zulu"])
        XCTAssertEqual(packages.map(\.repositoryURL), [
            "https://example.com/Alpha/Package",
            "https://example.com/Zulu/Package",
        ])
        XCTAssertEqual(packages[1].linkedProducts, [
            LinkedProduct(productName: "AlphaFeature", targetName: "Alpha"),
            LinkedProduct(productName: "ZuluFeature", targetName: "Zulu"),
        ])
    }

    func testSortsEquivalentPackageURLsByRequirementAndProducts() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeEquivalentURLPackageProject(in: root)
        let packages = try XcodeProjectAnalyzer()
            .analyzeProject(at: project.path)
            .swiftPMState
            .packages

        XCTAssertEqual(packages.map(\.requirement), [
            .exact("1.0.0"),
            .exact("1.0.0"),
            .branch("develop"),
        ])
        XCTAssertEqual(packages[0].linkedProducts.map(\.productName), ["AlphaFeature"])
        XCTAssertEqual(packages[1].linkedProducts.map(\.productName), ["ZuluFeature"])
        XCTAssertEqual(packages[2].linkedProducts, [])
    }

    func testProfilesAllSupportedLanguagesFromPBXMetadataWithoutReadingSources() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeSourceProfileProject(
            in: root,
            fileTypes: [
                "sourcecode.cpp.cpp",
                "sourcecode.c.objc",
                "sourcecode.swift",
                "sourcecode.cpp.objcpp",
                "sourcecode.c.c",
                "sourcecode.swift",
            ]
        )

        let target = try analyzedTarget(in: project)

        XCTAssertEqual(
            target.sourceProfile,
            TargetSourceProfile(
                languages: [.swift, .objectiveC, .objectiveCPlusPlus, .c, .cPlusPlus],
                completeness: .complete
            )
        )
    }

    func testUnknownTypeAndMissingFileReferenceMakeProfileIncomplete() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeSourceProfileProject(
            in: root,
            fileTypes: ["sourcecode.swift", "sourcecode.unknown"],
            includeMissingFileReference: true
        )

        let target = try analyzedTarget(in: project)

        XCTAssertEqual(
            target.sourceProfile,
            TargetSourceProfile(languages: [.swift], completeness: .incomplete)
        )
    }

    func testFileSystemSynchronizedRootGroupMakesProfileIncomplete() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeSourceProfileProject(
            in: root,
            fileTypes: ["sourcecode.swift"],
            hasFileSystemSynchronizedRootGroup: true
        )

        let target = try analyzedTarget(in: project)

        XCTAssertEqual(
            target.sourceProfile,
            TargetSourceProfile(languages: [.swift], completeness: .incomplete)
        )
    }

    func testTargetWithoutSourcesHasCompleteEmptyProfile() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeProject(
            in: root,
            configurationNames: ["Debug"],
            projectSettings: [:],
            targetSettings: [:]
        )

        let target = try analyzedTarget(in: project)

        XCTAssertEqual(
            target.sourceProfile,
            TargetSourceProfile(languages: [], completeness: .complete)
        )
    }

    func testDetectsConfirmedCarthageXcodeIntegration() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeCarthageProject(in: root, includesCarthage: true)
        let result = try XcodeProjectAnalyzer().analyzeProject(at: project.path)

        XCTAssertTrue(result.hasCarthageIntegration)
    }

    func testDoesNotTreatUnrelatedFrameworkOrCommentAsCarthage() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = try writeCarthageProject(in: root, includesCarthage: false)
        let result = try XcodeProjectAnalyzer().analyzeProject(at: project.path)

        XCTAssertFalse(result.hasCarthageIntegration)
    }

    private func analyzedTarget(in project: URL) throws -> TargetInfo {
        let result = try XcodeProjectAnalyzer().analyzeProject(at: project.path)
        guard let target = result.targets.first(where: { $0.name == "Example" }) else {
            throw TestError.missingTarget
        }
        return target
    }

    private func makeDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftXcodeAnalyzer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeProject(
        in root: URL,
        configurationNames: [String],
        projectConfigurationNames: [String]? = nil,
        projectSettings: [String: [String: String]],
        targetSettings: [String: [String: String]],
        projectBaseConfigurationPath: String? = nil,
        targetBaseConfigurationPath: String? = nil
    ) throws -> URL {
        let projectURL = root.appendingPathComponent("Example.xcodeproj")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let resolvedProjectConfigurationNames = projectConfigurationNames ?? configurationNames

        let projectConfigurations = resolvedProjectConfigurationNames.enumerated().map { index, name in
            configuration(
                identifier: "10000000000000000000000\(index)",
                name: name,
                settings: projectSettings[name] ?? [:],
                baseConfigurationReference: projectBaseConfigurationPath == nil ? nil : "300000000000000000000001"
            )
        }.joined(separator: "\n")

        let targetConfigurations = configurationNames.enumerated().map { index, name in
            configuration(
                identifier: "20000000000000000000000\(index)",
                name: name,
                settings: targetSettings[name] ?? [:],
                baseConfigurationReference: targetBaseConfigurationPath == nil ? nil : "300000000000000000000002"
            )
        }.joined(separator: "\n")

        let projectConfigurationReferences = resolvedProjectConfigurationNames.indices
            .map { "10000000000000000000000\($0)" }
            .joined(separator: ", ")
        let targetConfigurationReferences = configurationNames.indices
            .map { "20000000000000000000000\($0)" }
            .joined(separator: ", ")

        let configurationReferences = [
            projectBaseConfigurationPath.map {
                fileReference(identifier: "300000000000000000000001", path: $0)
            },
            targetBaseConfigurationPath.map {
                fileReference(identifier: "300000000000000000000002", path: $0)
            },
        ].compactMap { $0 }.joined(separator: "\n")

        let mainGroupChildren = [
            projectBaseConfigurationPath.map { _ in "300000000000000000000001" },
            targetBaseConfigurationPath.map { _ in "300000000000000000000002" },
        ].compactMap { $0 }.joined(separator: ", ")

        let contents = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            classes = {};
            objectVersion = 56;
            objects = {
        \(configurationReferences)
        \(projectConfigurations)
        \(targetConfigurations)
                400000000000000000000001 = {
                    isa = PBXGroup;
                    children = (\(mainGroupChildren));
                    sourceTree = \"<group>\";
                };
                500000000000000000000001 = {
                    isa = PBXProject;
                    buildConfigurationList = 600000000000000000000001;
                    compatibilityVersion = \"Xcode 14.0\";
                    mainGroup = 400000000000000000000001;
                    projectDirPath = \"\";
                    projectRoot = \"\";
                    targets = (700000000000000000000001);
                };
                600000000000000000000001 = {
                    isa = XCConfigurationList;
                    buildConfigurations = (\(projectConfigurationReferences));
                    defaultConfigurationIsVisible = 0;
                    defaultConfigurationName = Debug;
                };
                600000000000000000000002 = {
                    isa = XCConfigurationList;
                    buildConfigurations = (\(targetConfigurationReferences));
                    defaultConfigurationIsVisible = 0;
                    defaultConfigurationName = Debug;
                };
                700000000000000000000001 = {
                    isa = PBXNativeTarget;
                    buildConfigurationList = 600000000000000000000002;
                    buildPhases = ();
                    buildRules = ();
                    dependencies = ();
                    name = Example;
                    productName = Example;
                    productType = \"com.apple.product-type.application\";
                };
            };
            rootObject = 500000000000000000000001;
        }
        """

        try write(contents, to: projectURL.appendingPathComponent("project.pbxproj"))
        return projectURL
    }

    private func writeSwiftPackageProject(in root: URL) throws -> URL {
        let projectURL = root.appendingPathComponent("Packages.xcodeproj")
        let mainGroup = PBXGroup(children: [], sourceTree: .group, name: "Main")
        let projectConfigurations = XCConfigurationList()
        let alphaConfigurations = XCConfigurationList()
        let zuluConfigurations = XCConfigurationList()
        let alphaFrameworks = PBXFrameworksBuildPhase(files: [])
        let zuluFrameworks = PBXFrameworksBuildPhase(files: [])
        let alphaTarget = PBXNativeTarget(
            name: "Alpha",
            buildConfigurationList: alphaConfigurations,
            buildPhases: [alphaFrameworks],
            productName: "Alpha.app",
            productType: .application
        )
        let zuluTarget = PBXNativeTarget(
            name: "Zulu",
            buildConfigurationList: zuluConfigurations,
            buildPhases: [zuluFrameworks],
            productName: "Zulu.app",
            productType: .application
        )
        let rootProject = PBXProject(
            name: "Packages",
            buildConfigurationList: projectConfigurations,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            targets: [zuluTarget, alphaTarget]
        )
        let pbxproj = PBXProj(
            rootObject: rootProject,
            objectVersion: 56,
            archiveVersion: 1,
            classes: [:],
            objects: []
        )
        [
            mainGroup,
            projectConfigurations,
            alphaConfigurations,
            zuluConfigurations,
            alphaFrameworks,
            zuluFrameworks,
            alphaTarget,
            zuluTarget,
            rootProject,
        ].forEach { pbxproj.add(object: $0) }
        try XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
            .write(path: Path(projectURL.path))

        let editor = XcodeProjectEditor()
        try editor.addSwiftPMPackage(
            repositoryURL: "https://example.com/Zulu/Package",
            requirement: .exact("1.0.0"),
            to: projectURL.path
        )
        try editor.addSwiftPMPackage(
            repositoryURL: "https://example.com/Alpha/Package",
            requirement: .exact("1.0.0"),
            to: projectURL.path
        )
        try editor.linkSwiftPMProduct(
            productName: "ZuluFeature",
            toTarget: "Zulu",
            repositoryURL: "https://example.com/Zulu/Package",
            in: projectURL.path
        )
        try editor.linkSwiftPMProduct(
            productName: "AlphaFeature",
            toTarget: "Alpha",
            repositoryURL: "https://example.com/Zulu/Package",
            in: projectURL.path
        )
        return projectURL
    }

    private func writeEquivalentURLPackageProject(in root: URL) throws -> URL {
        let projectURL = root.appendingPathComponent("EquivalentPackages.xcodeproj")
        let repositoryURL = "https://example.com/Shared/Package"
        let alphaPackage = XCRemoteSwiftPackageReference(
            repositoryURL: repositoryURL,
            versionRequirement: .exact("1.0.0"),
            traits: ["Alpha"]
        )
        let zuluPackage = XCRemoteSwiftPackageReference(
            repositoryURL: repositoryURL,
            versionRequirement: .exact("1.0.0"),
            traits: ["Zulu"]
        )
        let branchPackage = XCRemoteSwiftPackageReference(
            repositoryURL: repositoryURL,
            versionRequirement: .branch("develop")
        )
        let alphaProduct = XCSwiftPackageProductDependency(
            productName: "AlphaFeature",
            package: alphaPackage
        )
        let zuluProduct = XCSwiftPackageProductDependency(
            productName: "ZuluFeature",
            package: zuluPackage
        )
        let mainGroup = PBXGroup(children: [], sourceTree: .group, name: "Main")
        let projectConfigurations = XCConfigurationList()
        let targetConfigurations = XCConfigurationList()
        let target = PBXNativeTarget(
            name: "App",
            buildConfigurationList: targetConfigurations,
            productName: "App.app",
            productType: .application
        )
        target.packageProductDependencies = [zuluProduct, alphaProduct]
        let rootProject = PBXProject(
            name: "EquivalentPackages",
            buildConfigurationList: projectConfigurations,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            targets: [target],
            packages: [branchPackage, zuluPackage, alphaPackage]
        )
        let pbxproj = PBXProj(
            rootObject: rootProject,
            objectVersion: 56,
            archiveVersion: 1,
            classes: [:],
            objects: []
        )
        [
            mainGroup,
            projectConfigurations,
            targetConfigurations,
            alphaPackage,
            zuluPackage,
            branchPackage,
            alphaProduct,
            zuluProduct,
            target,
            rootProject,
        ].forEach { pbxproj.add(object: $0) }
        try XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
            .write(path: Path(projectURL.path))
        return projectURL
    }

    private func writeSourceProfileProject(
        in root: URL,
        fileTypes: [String],
        includeMissingFileReference: Bool = false,
        hasFileSystemSynchronizedRootGroup: Bool = false
    ) throws -> URL {
        let projectURL = root.appendingPathComponent("SourceProfile.xcodeproj")
        let sourceReferences = fileTypes.enumerated().map { index, fileType in
            PBXFileReference(
                sourceTree: .group,
                lastKnownFileType: fileType,
                path: "Source\(index)"
            )
        }
        var buildFiles = sourceReferences.map { PBXBuildFile(file: $0) }
        if includeMissingFileReference {
            buildFiles.append(PBXBuildFile())
        }

        let sourcesBuildPhase = PBXSourcesBuildPhase(files: buildFiles)
        let synchronizedGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group,
            path: "SynchronizedSources"
        )
        let mainGroupChildren: [PBXFileElement] = sourceReferences
            + (hasFileSystemSynchronizedRootGroup ? [synchronizedGroup] : [])
        let mainGroup = PBXGroup(children: mainGroupChildren, sourceTree: .group, name: "Main")
        let projectConfigurations = XCConfigurationList()
        let targetConfigurations = XCConfigurationList()
        let target = PBXNativeTarget(
            name: "Example",
            buildConfigurationList: targetConfigurations,
            buildPhases: [sourcesBuildPhase],
            productName: "Example.app",
            productType: .application
        )
        target.fileSystemSynchronizedGroups = hasFileSystemSynchronizedRootGroup
            ? [synchronizedGroup]
            : nil
        let rootProject = PBXProject(
            name: "SourceProfile",
            buildConfigurationList: projectConfigurations,
            compatibilityVersion: "Xcode 16.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            targets: [target]
        )
        let pbxproj = PBXProj(
            rootObject: rootProject,
            objectVersion: 77,
            archiveVersion: 1,
            classes: [:],
            objects: []
        )
        let optionalObjects: [PBXObject] = hasFileSystemSynchronizedRootGroup
            ? [synchronizedGroup]
            : []
        var objects: [PBXObject] = []
        objects.append(contentsOf: sourceReferences)
        objects.append(contentsOf: buildFiles)
        objects.append(contentsOf: [
            sourcesBuildPhase,
            mainGroup,
            projectConfigurations,
            targetConfigurations,
            target,
            rootProject,
        ])
        objects.append(contentsOf: optionalObjects)
        objects.forEach { pbxproj.add(object: $0) }

        try XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
            .write(path: Path(projectURL.path))
        return projectURL
    }

    private func writeCarthageProject(in root: URL, includesCarthage: Bool) throws -> URL {
        let projectURL = root.appendingPathComponent("CarthageIntegration.xcodeproj")
        let frameworkReference = PBXFileReference(
            sourceTree: .group,
            lastKnownFileType: "wrapper.framework",
            path: includesCarthage
                ? "Carthage/Build/iOS/Legacy.framework"
                : "Vendor/Legacy.xcframework"
        )
        let frameworkBuildFile = PBXBuildFile(file: frameworkReference)
        let frameworks = PBXFrameworksBuildPhase(files: [frameworkBuildFile])
        let script = PBXShellScriptBuildPhase(
            shellScript: includesCarthage
                ? "/usr/local/bin/carthage copy-frameworks"
                : "# $(SRCROOT)/Carthage/Build/Legacy.framework\n# carthage copy-frameworks\necho complete"
        )
        let mainGroup = PBXGroup(
            children: [frameworkReference],
            sourceTree: .group,
            name: "Main"
        )
        let projectConfigurations = XCConfigurationList()
        let targetConfigurations = XCConfigurationList()
        let target = PBXNativeTarget(
            name: "Example",
            buildConfigurationList: targetConfigurations,
            buildPhases: [frameworks, script],
            productName: "Example.app",
            productType: .application
        )
        let rootProject = PBXProject(
            name: "CarthageIntegration",
            buildConfigurationList: projectConfigurations,
            compatibilityVersion: "Xcode 15.0",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup,
            targets: [target]
        )
        let pbxproj = PBXProj(
            rootObject: rootProject,
            objectVersion: 56,
            archiveVersion: 1,
            classes: [:],
            objects: []
        )
        [
            frameworkReference,
            frameworkBuildFile,
            frameworks,
            script,
            mainGroup,
            projectConfigurations,
            targetConfigurations,
            target,
            rootProject,
        ].forEach { pbxproj.add(object: $0) }
        try XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
            .write(path: Path(projectURL.path))
        return projectURL
    }

    private func configuration(
        identifier: String,
        name: String,
        settings: [String: String],
        baseConfigurationReference: String?
    ) -> String {
        let buildSettings = settings.sorted { $0.key < $1.key }.map {
            "\(quotedPBXString($0.key)) = \(quotedPBXString($0.value));"
        }.joined(separator: " ")
        let baseConfiguration = baseConfigurationReference.map {
            "baseConfigurationReference = \($0);"
        } ?? ""

        return """
                \(identifier) = {
                    isa = XCBuildConfiguration;
                    \(baseConfiguration)
                    buildSettings = { \(buildSettings) };
                    name = \(name);
                };
        """
    }

    private func fileReference(identifier: String, path: String) -> String {
        """
                \(identifier) = {
                    isa = PBXFileReference;
                    lastKnownFileType = text.xcconfig;
                    path = \(path);
                    sourceTree = \"<group>\";
                };
        """
    }

    private func quotedPBXString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private enum TestError: Error {
        case missingTarget
    }
}
