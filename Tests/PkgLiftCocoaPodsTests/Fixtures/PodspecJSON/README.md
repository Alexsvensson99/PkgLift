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

The fixtures exercise declared syntax only. Their presence does not verify a
CocoaPods-to-SwiftPM registry mapping or build equivalence.
