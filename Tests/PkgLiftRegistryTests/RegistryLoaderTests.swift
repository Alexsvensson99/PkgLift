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
        XCTAssertEqual(alamofire?.swiftpm.minimumVersion, "5.0.0")
        XCTAssertEqual(alamofire?.swiftpm.supportedConsumerLanguages, [.swift])
        XCTAssertEqual(alamofire?.migration.confidence, .verified)
        
        let firebaseAnalytics = await loader.lookup(name: "Firebase", subspec: "Analytics")
        XCTAssertNotNil(firebaseAnalytics)
        XCTAssertEqual(firebaseAnalytics?.swiftpm.products, ["FirebaseAnalytics"])
        XCTAssertEqual(firebaseAnalytics?.swiftpm.minimumVersion, "8.0.0")
        XCTAssertEqual(
            firebaseAnalytics?.swiftpm.supportedConsumerLanguages,
            [.swift, .objectiveC]
        )

        let directFirebaseMappings = [
            ("FirebaseAnalytics", "FirebaseAnalytics"),
            ("FirebaseAuth", "FirebaseAuth"),
            ("FirebaseCrashlytics", "FirebaseCrashlytics"),
            ("FirebaseFirestore", "FirebaseFirestore"),
            ("FirebaseMessaging", "FirebaseMessaging"),
            ("FirebaseRemoteConfig", "FirebaseRemoteConfig"),
            ("FirebaseStorage", "FirebaseStorage"),
        ]
        for (podName, productName) in directFirebaseMappings {
            let mapping = await loader.lookup(name: podName)
            XCTAssertEqual(mapping?.swiftpm.products, [productName])
            XCTAssertEqual(mapping?.swiftpm.minimumVersion, "11.12.0")
            XCTAssertEqual(
                mapping?.swiftpm.supportedConsumerLanguages,
                [.swift, .objectiveC]
            )
        }

        let newFirebaseSubspecMappings = [
            ("Auth", "FirebaseAuth"),
            ("Firestore", "FirebaseFirestore"),
            ("RemoteConfig", "FirebaseRemoteConfig"),
            ("Storage", "FirebaseStorage"),
        ]
        for (subspec, productName) in newFirebaseSubspecMappings {
            let mapping = await loader.lookup(name: "Firebase", subspec: subspec)
            XCTAssertEqual(mapping?.pod.fullName, "Firebase/\(subspec)")
            XCTAssertEqual(mapping?.swiftpm.products, [productName])
            XCTAssertEqual(mapping?.swiftpm.minimumVersion, "11.12.0")
            XCTAssertEqual(
                mapping?.swiftpm.supportedConsumerLanguages,
                [.swift, .objectiveC]
            )
        }

        let lottie = await loader.lookup(name: "lottie-ios")
        XCTAssertEqual(lottie?.swiftpm.repository, "https://github.com/airbnb/lottie-ios")
        XCTAssertEqual(lottie?.swiftpm.products, ["Lottie"])
        XCTAssertEqual(lottie?.swiftpm.minimumVersion, "3.2.2")
        XCTAssertEqual(lottie?.swiftpm.supportedConsumerLanguages, [.swift])
        XCTAssertEqual(lottie?.migration.confidence, .verified)

        let firebaseBase = await loader.lookup(name: "Firebase")
        let firebaseCore = await loader.lookup(name: "Firebase", subspec: "Core")
        let firebaseUnknown = await loader.lookup(name: "Firebase", subspec: "Unknown")
        let firebaseNested = await loader.lookup(name: "Firebase", subspec: "Auth/Extra")
        XCTAssertNil(firebaseBase)
        XCTAssertNil(firebaseCore)
        XCTAssertNil(firebaseUnknown)
        XCTAssertNil(firebaseNested)

        let undeclaredSubspec = await loader.lookup(name: "SDWebImage", subspec: "Core")
        XCTAssertNil(undeclaredSubspec)
    }

    func testBundledRegistryLocatorResolvesExecutableSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftRegistrySymlink-\(UUID().uuidString)")
        let installDirectory = root.appendingPathComponent("libexec/pkglift")
        let binDirectory = root.appendingPathComponent("bin")
        let registryDirectory = installDirectory
            .appendingPathComponent("PkgLift_PkgLiftRegistry.bundle")
            .appendingPathComponent("BundledRegistry")
        let executable = installDirectory.appendingPathComponent("pkglift")
        let executableSymlink = binDirectory.appendingPathComponent("pkglift")

        try FileManager.default.createDirectory(at: registryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try Data().write(to: executable)
        try FileManager.default.createSymbolicLink(at: executableSymlink, withDestinationURL: executable)
        defer { try? FileManager.default.removeItem(at: root) }

        let candidates = BundledRegistryLocator.candidateURLs(
            mainBundleURL: binDirectory,
            executableURL: executableSymlink
        )

        XCTAssertEqual(
            BundledRegistryLocator.locate(in: candidates)?.standardizedFileURL,
            registryDirectory.standardizedFileURL
        )
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

    func testMissingConfiguredRegistryDirectoryThrowsInvalidPathBeforeBundledFallback() async throws {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftMissingRegistry-\(UUID().uuidString)")
        let loader = RegistryLoader(configPaths: [missingDirectory], useBundledRegistry: true)

        do {
            try await loader.load()
            XCTFail("Expected the missing configured registry path to be rejected")
        } catch let error as RegistryError {
            guard case .invalidPath(let path) = error else {
                return XCTFail("Expected invalidPath, got \(error)")
            }
            XCTAssertEqual(path, missingDirectory.path)
        }
    }

    func testMalformedYAMLManifestIsRejectedDuringLoad() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftMalformedYAML-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "schemaVersion: [1".write(
            to: directory.appendingPathComponent("Malformed.yml"),
            atomically: true,
            encoding: .utf8
        )
        let loader = RegistryLoader(configPaths: [directory], useBundledRegistry: false)

        do {
            try await loader.load()
            XCTFail("Expected malformed YAML manifest to be rejected")
        } catch let error as RegistryError {
            guard case .parsingError(let path, _) = error else {
                return XCTFail("Expected parsingError, got \(error)")
            }
            XCTAssertEqual(URL(fileURLWithPath: path).lastPathComponent, "Malformed.yml")
        }
    }

    func testManifestMissingRequiredFieldIsRejectedDuringLoad() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftIncompleteManifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mapping = """
        schemaVersion: 1
        pod:
          name: IncompletePod
        swiftpm:
          repository: https://example.com/owner/repository
          products: [IncompletePod]
        """
        try mapping.write(
            to: directory.appendingPathComponent("IncompletePod.yml"),
            atomically: true,
            encoding: .utf8
        )
        let loader = RegistryLoader(configPaths: [directory], useBundledRegistry: false)

        do {
            try await loader.load()
            XCTFail("Expected manifest with missing migration field to be rejected")
        } catch let error as RegistryError {
            guard case .parsingError = error else {
                return XCTFail("Expected parsingError, got \(error)")
            }
        }
    }

    func testWrongFieldTypeIsRejectedDuringLoad() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftWrongFieldType-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mapping = """
        schemaVersion: 1
        pod:
          name: WrongTypePod
        swiftpm:
          repository: https://example.com/owner/repository
          products: WrongTypePod
        migration:
          confidence: verified
        """
        try mapping.write(
            to: directory.appendingPathComponent("WrongTypePod.yml"),
            atomically: true,
            encoding: .utf8
        )
        let loader = RegistryLoader(configPaths: [directory], useBundledRegistry: false)

        do {
            try await loader.load()
            XCTFail("Expected wrong field type to be rejected")
        } catch let error as RegistryError {
            guard case .parsingError = error else {
                return XCTFail("Expected parsingError, got \(error)")
            }
        }
    }

    func testUnsupportedSchemaVersionIsRejectedDuringLoad() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftUnsupportedSchema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mapping = """
        schemaVersion: 99
        pod:
          name: FuturePod
        swiftpm:
          repository: https://example.com/owner/repository
          products: [FuturePod]
        migration:
          confidence: verified
        """
        try mapping.write(
            to: directory.appendingPathComponent("FuturePod.yml"),
            atomically: true,
            encoding: .utf8
        )
        let loader = RegistryLoader(configPaths: [directory], useBundledRegistry: false)

        do {
            try await loader.load()
            XCTFail("Expected unsupported schema to be rejected")
        } catch let error as RegistryError {
            guard case .validationFailed(let errors) = error else {
                return XCTFail("Expected validationFailed, got \(error)")
            }
            XCTAssertEqual(errors.map(\.fieldPath), ["schemaVersion"])
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

    func testUnknownConsumerLanguageIsRejectedDuringLoad() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftRegistryLanguages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mapping = """
        schemaVersion: 1
        pod:
          name: UnknownLanguagePod
        swiftpm:
          repository: https://example.com/owner/repository
          products: [UnknownLanguagePod]
          supportedConsumerLanguages: [swift, kotlin]
        migration:
          confidence: verified
        """
        try mapping.write(
            to: directory.appendingPathComponent("UnknownLanguagePod.yml"),
            atomically: true,
            encoding: .utf8
        )
        let loader = RegistryLoader(configPaths: [directory], useBundledRegistry: false)

        do {
            try await loader.load()
            XCTFail("Expected unknown consumer language to be rejected")
        } catch let error as RegistryError {
            guard case .parsingError = error else {
                return XCTFail("Expected parsingError, got \(error)")
            }
        }
    }
}
