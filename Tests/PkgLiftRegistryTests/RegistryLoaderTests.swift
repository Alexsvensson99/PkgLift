import XCTest
import PkgLiftCore
@testable import PkgLiftRegistry

final class RegistryLoaderTests: XCTestCase {
    
    func testLoadBundledRegistry() async throws {
        let loader = RegistryLoader(useBundledRegistry: true)
        try await loader.load()
        
        let mappings = await loader.getMappings()
        XCTAssertFalse(mappings.isEmpty)
        
        let alamofire = await loader.lookup(name: "Alamofire")
        XCTAssertNotNil(alamofire)
        XCTAssertEqual(alamofire?.swiftpm.repository, "https://github.com/Alamofire/Alamofire")
        XCTAssertEqual(alamofire?.swiftpm.products, ["Alamofire"])
        XCTAssertEqual(alamofire?.migration.confidence, .verified)
        
        let firebaseAnalytics = await loader.lookup(name: "Firebase", subspec: "Analytics")
        XCTAssertNotNil(firebaseAnalytics)
        XCTAssertEqual(firebaseAnalytics?.swiftpm.products, ["FirebaseAnalytics"])
    }

    func testInvalidLocalOverrideIsRejectedDuringNormalLoad() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftRegistry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mapping = """
        schemaVersion: 1
        pod:
          name: UnsafePod
        swiftpm:
          repository: ""
          products: []
        migration:
          confidence: verified
        """
        try mapping.write(
            to: directory.appendingPathComponent("UnsafePod.yml"),
            atomically: true,
            encoding: .utf8
        )
        let loader = RegistryLoader(localOverridePath: directory, useBundledRegistry: false)

        do {
            try await loader.load()
            XCTFail("Expected invalid mapping to be rejected")
        } catch let error as RegistryError {
            guard case .validationFailed(let errors) = error else {
                return XCTFail("Expected validationFailed, got \(error)")
            }
            XCTAssertTrue(errors.contains { $0.fieldPath == "swiftpm.repository" })
            XCTAssertTrue(errors.contains { $0.fieldPath == "swiftpm.products" })
        }
    }

    func testSourceRegistryMatchesBundledRegistry() async throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceLoader = RegistryLoader(
            configPaths: [repositoryRoot.appendingPathComponent("Registry")],
            useBundledRegistry: false
        )
        let bundledLoader = RegistryLoader(useBundledRegistry: true)
        try await sourceLoader.load()
        try await bundledLoader.load()

        let source = Dictionary(
            uniqueKeysWithValues: await sourceLoader.getMappings().map { ($0.pod.fullName, $0) }
        )
        let bundled = Dictionary(
            uniqueKeysWithValues: await bundledLoader.getMappings().map { ($0.pod.fullName, $0) }
        )

        XCTAssertEqual(source, bundled)
    }

    func testDuplicateIdentifierInOneRegistrySourceIsRejected() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftRegistryDuplicates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mapping = """
        schemaVersion: 1
        pod:
          name: DuplicatePod
        swiftpm:
          repository: https://example.com/owner/repository
          products: [DuplicatePod]
        migration:
          confidence: verified
        """
        try mapping.write(to: directory.appendingPathComponent("One.yml"), atomically: true, encoding: .utf8)
        try mapping.write(to: directory.appendingPathComponent("Two.yml"), atomically: true, encoding: .utf8)
        let loader = RegistryLoader(configPaths: [directory], useBundledRegistry: false)

        do {
            try await loader.load()
            XCTFail("Expected duplicate mapping refusal")
        } catch let error as RegistryError {
            guard case .validationFailed = error else {
                return XCTFail("Expected validationFailed, got \(error)")
            }
        }
    }
}
