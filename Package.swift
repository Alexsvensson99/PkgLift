// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PkgLift",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "pkglift", targets: ["PkgLiftCLI"]),
        .library(name: "PkgLiftCore", targets: ["PkgLiftCore"]),
        .library(name: "PkgLiftCocoaPods", targets: ["PkgLiftCocoaPods"]),
        .library(name: "PkgLiftXcode", targets: ["PkgLiftXcode"]),
        .library(name: "PkgLiftRegistry", targets: ["PkgLiftRegistry"]),
        .library(name: "PkgLiftMigration", targets: ["PkgLiftMigration"]),
        .library(name: "PkgLiftVerification", targets: ["PkgLiftVerification"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "9.13.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0"),
    ],
    targets: [
        // MARK: - Executable

        .executableTarget(
            name: "PkgLiftCLI",
            dependencies: [
                "PkgLiftCore",
                "PkgLiftCocoaPods",
                "PkgLiftXcode",
                "PkgLiftRegistry",
                "PkgLiftMigration",
                "PkgLiftVerification",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // MARK: - Libraries

        .target(
            name: "PkgLiftCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .target(
            name: "PkgLiftCocoaPods",
            dependencies: [
                "PkgLiftCore",
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .target(
            name: "PkgLiftXcode",
            dependencies: [
                "PkgLiftCore",
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .target(
            name: "PkgLiftRegistry",
            dependencies: [
                "PkgLiftCore",
                .product(name: "Yams", package: "Yams"),
            ],
            resources: [
                .copy("BundledRegistry"),
            ]
        ),
        .target(
            name: "PkgLiftMigration",
            dependencies: [
                "PkgLiftCore",
                "PkgLiftCocoaPods",
                "PkgLiftXcode",
                "PkgLiftRegistry",
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .target(
            name: "PkgLiftVerification",
            dependencies: [
                "PkgLiftCore",
                "PkgLiftXcode",
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),

        // MARK: - Test Targets

        .testTarget(
            name: "PkgLiftCoreTests",
            dependencies: ["PkgLiftCore"]
        ),
        .testTarget(
            name: "PkgLiftCocoaPodsTests",
            dependencies: ["PkgLiftCocoaPods", "PkgLiftCore"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
        .testTarget(
            name: "PkgLiftRegistryTests",
            dependencies: ["PkgLiftRegistry", "PkgLiftCore"]
        ),
        .testTarget(
            name: "PkgLiftMigrationTests",
            dependencies: ["PkgLiftMigration", "PkgLiftCore", "PkgLiftCocoaPods", "PkgLiftRegistry"]
        ),
        .testTarget(
            name: "PkgLiftVerificationTests",
            dependencies: [
                "PkgLiftVerification",
                "PkgLiftCore",
                "PkgLiftXcode",
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .testTarget(
            name: "PkgLiftXcodeTests",
            dependencies: [
                "PkgLiftXcode",
                "PkgLiftCore",
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
        .testTarget(
            name: "PkgLiftCLITests",
            dependencies: [
                "PkgLiftCLI",
                "PkgLiftCore",
                "PkgLiftXcode",
                .product(name: "XcodeProj", package: "XcodeProj"),
            ]
        ),
    ]
)
