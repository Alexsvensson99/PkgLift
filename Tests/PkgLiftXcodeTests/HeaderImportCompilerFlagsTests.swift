import XCTest
@testable import PkgLiftXcode

final class HeaderImportCompilerFlagsTests: XCTestCase {
    func testAcceptsReviewedCAndSwiftModuleMapFlags() {
        let configuration = "$(inherited) -fmodule-map-file=\"${PODS_CONFIGURATION_BUILD_DIR}/KeychainAccess/KeychainAccess.modulemap\" -fmodule-map-file=\"${PODS_ROOT}/Headers/Public/SDWebImage/SDWebImage.modulemap\""
        XCTAssertTrue(HeaderImportCompilerFlags.accepts(value: configuration, setting: "OTHER_CFLAGS"))
        let swift = "$(inherited) -D COCOAPODS -Xcc -fmodule-map-file=\"${PODS_CONFIGURATION_BUILD_DIR}/KeychainAccess/KeychainAccess.modulemap\" -Xcc -fmodule-map-file=\"${PODS_ROOT}/Headers/Public/SDWebImage/SDWebImage.modulemap\""
        XCTAssertTrue(HeaderImportCompilerFlags.accepts(value: swift, setting: "OTHER_SWIFT_FLAGS"))
    }

    func testAcceptsOnlySimpleSettingSpecificMacros() {
        XCTAssertTrue(HeaderImportCompilerFlags.accepts(value: "$(inherited) -DDEBUG -D FEATURE=1 -U OLD", setting: "OTHER_CFLAGS"))
        XCTAssertTrue(HeaderImportCompilerFlags.accepts(value: "$(inherited) -DDEBUG -D FEATURE", setting: "OTHER_SWIFT_FLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-D FEATURE=1", setting: "OTHER_SWIFT_FLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-U OLD", setting: "OTHER_SWIFT_FLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-U OLD=1", setting: "OTHER_CFLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-Xcc -fmodule-map-file=${PODS_ROOT}/Headers/Public/SDWebImage/SDWebImage.modulemap", setting: "OTHER_CFLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-fmodule-map-file=${PODS_ROOT}/Headers/Public/SDWebImage/SDWebImage.modulemap", setting: "OTHER_SWIFT_FLAGS"))
        XCTAssertTrue(HeaderImportCompilerFlags.accepts(value: "$(inherited)", setting: "OTHER_CPLUSPLUSFLAGS"))
    }

    func testRecognizedSettingsAllowEmptyWhitespaceAndEquivalentCPlusPlusGrammar() {
        for setting in ["OTHER_CFLAGS", "OTHER_CPLUSPLUSFLAGS", "OTHER_SWIFT_FLAGS"] {
            XCTAssertTrue(HeaderImportCompilerFlags.accepts(value: "", setting: setting), setting)
            XCTAssertTrue(HeaderImportCompilerFlags.accepts(value: " \t  ", setting: setting), setting)
        }
        XCTAssertTrue(HeaderImportCompilerFlags.accepts(value: "$(inherited) -DCPP=20 -U LEGACY", setting: "OTHER_CPLUSPLUSFLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "", setting: "OTHER_OBJC_FLAGS"))
    }

    func testAcceptsDuplicateReviewedFlagsInAnyOrder() {
        let first = "-fmodule-map-file=${PODS_ROOT}/Headers/Public/SDWebImage/SDWebImage.modulemap"
        let second = "-fmodule-map-file=${PODS_CONFIGURATION_BUILD_DIR}/KeychainAccess/KeychainAccess.modulemap"
        XCTAssertTrue(HeaderImportCompilerFlags.accepts(value: "$(inherited) \(second) -DDEBUG \(first) \(second)", setting: "OTHER_CFLAGS"))
        XCTAssertTrue(HeaderImportCompilerFlags.accepts(value: "-DDEBUG -Xcc \(second) $(inherited) -Xcc \(first) -Xcc \(second)", setting: "OTHER_SWIFT_FLAGS"))
    }

    func testRejectsUnreviewedModuleMapsAndInjectionSyntax() {
        let rejected = [
            "-fmodule-map-file=${PODS_ROOT}/Headers/Public/SDWebImage/../Private/Hidden.modulemap",
            "-fmodule-map-file=${PODS_ROOT}/Headers/Public//SDWebImage/SDWebImage.modulemap",
            "-fmodule-map-file=${PODS_ROOT}/Headers/Public/SDWebImage/Map.txt",
            "-fmodule-map-file=${PODS_ROOT}/Headers/Private/SDWebImage/SDWebImage.modulemap",
            "-fmodule-map-file=/tmp/Map.modulemap",
            "-include Prefix.pch",
            "-includeFoo",
            "-imacros Macros.h",
            "-include-pch Prefix.pch",
            "-import-objc-header Bridging.h",
            "-Xclang -load",
            "-I Headers",
            "-iquote Headers",
            "-isystem Headers",
            "-F Frameworks",
            "-fmodule-file=Module.pcm",
            "-x objective-c++",
            "@response",
            "-DNAME=string",
            "-D 1INVALID",
            "-DNAME\\ value",
            "-fmodule-map-file=\"${PODS_ROOT}/Headers/Public/SDWebImage/SDWebImage.modulemap"
        ]
        for value in rejected {
            XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: value, setting: "OTHER_CFLAGS"), value)
        }
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-Xcc", setting: "OTHER_SWIFT_FLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-Xcc -include", setting: "OTHER_SWIFT_FLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-Xcc -fmodule-map-file=${PODS_ROOT}/Headers/Public/SDWebImage/SDWebImage.modulemap -Xcc -include", setting: "OTHER_SWIFT_FLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-Xcc \"-fmodule-map-file=${PODS_ROOT}/Headers/Public/SDWebImage/SDWebImage.modulemap -include Prefix.h\"", setting: "OTHER_SWIFT_FLAGS"))
    }

    func testRejectsControlsAndConfiguredBounds() {
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-DDEBUG\n-DFEATURE", setting: "OTHER_CFLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: "-DDEBUG\u{7F}", setting: "OTHER_CFLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: String(repeating: "a", count: 64 * 1_024 + 1), setting: "OTHER_CFLAGS"))
        XCTAssertFalse(HeaderImportCompilerFlags.accepts(value: Array(repeating: "$(inherited)", count: 513).joined(separator: " "), setting: "OTHER_CFLAGS"))
    }
}
