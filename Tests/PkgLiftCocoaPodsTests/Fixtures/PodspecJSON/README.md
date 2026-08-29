# Podspec JSON fixture provenance

The pinned upstream fixtures in the table are exact, immutable copies of
CocoaPods Specs repository documents returned by the Trunk API on 2026-08-22.
Tests read only bundled files and never contact CocoaPods or an upstream
repository.

| Fixture | Immutable source | SHA-256 |
| --- | --- | --- |
| `KeychainAccess-4.2.2.podspec.json` | [`CocoaPods/Specs@79116ba`](https://raw.githubusercontent.com/CocoaPods/Specs/79116babc7079cdce2f90f34adbb2667532e637d/Specs/f/6/3/KeychainAccess/4.2.2/KeychainAccess.podspec.json) | `4608b1366f705163ed9804e812bec02925bf6b61bd9924b08c482eb2be34187c` |
| `DeviceKit-5.8.0.podspec.json` | [`CocoaPods/Specs@d9713ef`](https://raw.githubusercontent.com/CocoaPods/Specs/d9713efb46e5742f0817e67905d465f429c579c2/Specs/d/e/6/DeviceKit/5.8.0/DeviceKit.podspec.json) | `8297066280041cd75175167c32d79ee772a4b95a29c85ffc99cd468a6f3f15a5` |
| `CryptoSwift-1.10.0.podspec.json` | [`CocoaPods/Specs@2aec7cb`](https://raw.githubusercontent.com/CocoaPods/Specs/2aec7cbaad29fecb20f77859b261ef5af3de17af/Specs/3/e/b/CryptoSwift/1.10.0/CryptoSwift.podspec.json) | `e1da64dfdf81fa8aef911b44cb6ae36f05f2cf18dc36c3176070ff1d0eb73257` |

`RecursiveScopes-2.0.0.podspec.json` is a repository-authored adversarial
fixture for the pinned CocoaPods Core 1.17.0 profile. It combines root,
subspec, nested-subspec, and platform declarations without implying that an
upstream pod or SwiftPM package exists. Its SHA-256 is
`76074af53185960a37304152c61c365f99460ce6545bc27920d25f851aa024d2`.

`LinkageModules-3.0.0.podspec.json` is a repository-authored adversarial
fixture for the same pinned profile. It combines raw root, root-platform,
subspec, and subspec-platform linkage, module, header-layout, and vendored
input declarations. It deliberately includes `static_library`, which is not a
Podspec attribute in CocoaPods Core 1.17.0 and must remain explicit unknown
evidence. Its SHA-256 is
`70de6cdf72b353dd88cfc7a8913fd55830fb22686285b110b67c2843c75a41b5`.

`CompilationControls-4.0.0.podspec.json` is a repository-authored adversarial
fixture for the same pinned profile. It combines raw root, root-platform,
subspec, and subspec-platform compiler flags, build-setting maps, configuration
whitelists, Swift-version forms, ARC controls, and file-selection declarations.
Macro-, shell-, glob-, and traversal-looking strings are inert evidence. The
fixture also retains a deferred command, a deferred script phase, and an
unknown escaped key to prove that none is evaluated. Its SHA-256 is
`222d9ac7c6f92937481d16da7cd6f346a6956c6e73f8307f63837bc4c6686e01`.

The three `Assessment*-5.0.0.podspec.json` files are repository-authored,
immutable v0.5 release-gate fixtures for the same CocoaPods profile and the
`swift-tools-version/6.0` capability profile. Together with the release gate's
deliberately malformed public-model case, they cover every public assessment
reason, all four outcomes, every supported root platform block, a subspec
platform block, deterministic Codable output, and privacy-bounded dynamic
evidence paths. Secret-looking values are inert test data and must not appear
in an encoded assessment.

| Fixture | Intended strongest outcome | Fixture SHA-256 | Sorted assessment JSON SHA-256 |
| --- | --- | --- | --- |
| `AssessmentGenerated-5.0.0.podspec.json` | `requiresGeneratedMetadata` with every metadata-required reason at root scope | `dce61554ee3c126aa8ead34370772e0c38ad902f950fe4253e8411838f3b9dc3` | `c422c60d7b5883230b81252a5854ba910c74f247f317523860a8555e2b27ea24` |
| `AssessmentIndeterminate-5.0.0.podspec.json` | `indeterminate` with unknown, deferred, opaque, all-platform, and subspec evidence | `010645068c5789f41ad7d687345bc18b49e469a8297ff31cae44b30896e40e5f` | `adfa74dc73470899120051dbf61b6417c384b4c29a8c0ddfddd39293657356f5` |
| `AssessmentUnsupported-5.0.0.podspec.json` | `unsupported` with root, subspec, and platform refusal evidence | `e5caf6679f41a470d5d52223c69154fc6e758bc07a1ed8ad6fcae01656f88ede` | `c970a56bff12c4d9b17fdc9b57d565cc27395dd20b84223eee196ff5ca54db0f` |

Assessment hashes use `JSONEncoder` with `.sortedKeys` and
`.withoutEscapingSlashes`; they lock the schema, pinned profiles, outcome, and
canonical ordered-reason array rather than only repeatability within one run.

The fixtures exercise declared syntax only. Their presence does not verify a
CocoaPods-to-SwiftPM registry mapping or build equivalence.
