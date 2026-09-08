import Foundation
import Testing

@Suite("Local source inspection isolation")
struct LocalSourceIsolationTests {
    @Test("Disk inspection may only be orchestrated by the explicit Podspec command")
    func sourceBoundary() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var violations: [String] = []
        while let file = enumerator.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let relative = String(file.path.dropFirst(sources.path.count + 1))
            let text = try String(contentsOf: file, encoding: .utf8)
            let isInspector = relative.hasPrefix("PkgLiftInspection/")
            let isCommand = relative == "PkgLiftCLI/PodspecCommand.swift"
            if !isInspector && !isCommand,
               text.contains("PkgLiftInspection") || text.contains("LocalSourceInspector")
                || text.contains("LocalSourceInspectionReport") {
                violations.append(relative)
            }
            if isInspector,
               text.contains("import PkgLiftMigration") || text.contains("import PkgLiftXcode")
                || text.contains("import PkgLiftRegistry") || text.contains("import PkgLiftVerification")
                || text.contains("GeneratedPackageEvidence") || text.contains("GeneratedPackageBlueprint") {
                violations.append(relative)
            }
        }
        #expect(violations.isEmpty)
    }
}
