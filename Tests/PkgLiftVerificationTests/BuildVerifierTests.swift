import Foundation
import Testing
@testable import PkgLiftVerification

@Suite("BuildVerifier Tests")
struct BuildVerifierTests {
    @Test("Build arguments include explicit workspace settings in stable order")
    func buildArgumentsIncludeExplicitSettings() throws {
        let options = BuildVerificationOptions(
            configuration: " Release ",
            destination: "platform=iOS Simulator,name=iPhone 16 Pro",
            sdk: "iphonesimulator",
            derivedDataPath: "/tmp/Derived Data"
        )

        let arguments = try BuildVerifier.buildArguments(
            projectPath: "/tmp/My App.xcworkspace",
            scheme: " My App ",
            isWorkspace: true,
            options: options
        )

        #expect(arguments == [
            "build",
            "-scheme", "My App",
            "-workspace", "/tmp/My App.xcworkspace",
            "-configuration", "Release",
            "-destination", "platform=iOS Simulator,name=iPhone 16 Pro",
            "-sdk", "iphonesimulator",
            "-derivedDataPath", "/tmp/Derived Data",
        ])
    }

    @Test("Project build arguments preserve existing defaults")
    func projectBuildArgumentsPreserveDefaults() throws {
        let arguments = try BuildVerifier.buildArguments(
            projectPath: "App.xcodeproj",
            scheme: "App"
        )

        #expect(arguments == [
            "build",
            "-scheme", "App",
            "-project", "App.xcodeproj",
        ])
    }

    @Test("Package resolution uses only the derived-data override")
    func packageResolutionUsesOnlyDerivedData() throws {
        let options = BuildVerificationOptions(
            configuration: "Release",
            destination: "generic/platform=iOS Simulator",
            sdk: "iphonesimulator",
            derivedDataPath: "/tmp/Derived"
        )

        let arguments = try BuildVerifier.resolvePackageArguments(
            projectPath: "App.xcworkspace",
            isWorkspace: true,
            options: options
        )

        #expect(arguments == [
            "-resolvePackageDependencies",
            "-workspace", "App.xcworkspace",
            "-derivedDataPath", "/tmp/Derived",
        ])
    }

    @Test("Validation rejects empty and control-character values")
    func validationRejectsUnsafeValues() {
        do {
            _ = try BuildVerificationOptions(configuration: "   ").validated()
            Issue.record("Expected an empty configuration to be rejected")
        } catch let error as BuildVerificationOptionsError {
            #expect(error == .empty(field: "configuration"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try BuildVerifier.validatedScheme("App\nOther")
            Issue.record("Expected a control character to be rejected")
        } catch let error as BuildVerificationOptionsError {
            #expect(error == .controlCharacter(field: "scheme"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Redacted summaries do not expose the derived-data path")
    func redactedSummaryHidesPath() throws {
        let options = try BuildVerificationOptions(
            configuration: "Debug",
            destination: "platform=iOS Simulator,name=iPhone 16 Pro",
            sdk: "iphonesimulator",
            derivedDataPath: "/Users/alex/Secret Client/DerivedData"
        ).validated()

        #expect(options.redactedSummary.contains("configuration=Debug"))
        #expect(options.redactedSummary.contains("derivedDataPath=<provided>"))
        #expect(!options.redactedSummary.contains("alex"))
        #expect(!options.redactedSummary.contains("Secret Client"))
    }
}
