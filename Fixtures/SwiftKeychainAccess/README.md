# Swift KeychainAccess migration fixture

This repository-owned iOS 15 fixture is a Swift-only CocoaPods-to-SwiftPM
migration candidate. It contains one app target and one reusable consumer file:
`App/Consumer.swift`. `AppDelegate` references `RegistryConsumer.probe` as a
function value and therefore does not execute keychain access during a build.

The Podfile intentionally uses the exact literal declaration
`pod 'KeychainAccess', '4.2.2', :modular_headers => true` and does not use
`use_frameworks!`. PkgLift recognizes `use_frameworks!` as non-automatic, so
the upstream-documented framework form belongs in a separate negative REVIEW
test, never this AUTO candidate.

## Pinned upstream evidence

- CocoaPods Specs JSON: [`CocoaPods/Specs@79116ba`](https://raw.githubusercontent.com/CocoaPods/Specs/79116babc7079cdce2f90f34adbb2667532e637d/Specs/f/6/3/KeychainAccess/4.2.2/KeychainAccess.podspec.json), SHA-256 `4608b1366f705163ed9804e812bec02925bf6b61bd9924b08c482eb2be34187c`.
- KeychainAccess tag commit: [`84e546727d66f1adc5439debad16270d0fdd04e7`](https://github.com/kishikawakatsumi/KeychainAccess/commit/84e546727d66f1adc5439debad16270d0fdd04e7).
- SwiftPM manifest: [`Package.swift`](https://raw.githubusercontent.com/kishikawakatsumi/KeychainAccess/84e546727d66f1adc5439debad16270d0fdd04e7/Package.swift), product `KeychainAccess`.

The podspec supports iOS 9 and the manifest supports iOS 8; this iOS 15
fixture is within both. The podspec's macOS 10.9 and the manifest's macOS 10.10
minimums differ, so this fixture does not establish platform equivalence.

## Evidence boundary

The fixture itself is not consumer-build evidence. Do not add a KeychainAccess
registry mapping or classify it AUTO until CI has built both integration paths:

1. this exact CocoaPods baseline after `pod install --clean-install`;
2. a SwiftPM library consumer containing an identical copy of `App/Consumer.swift`.

After the mapping is added, the post-migration fixture must also pass
`pkglift verify --build` before integration.

The committed lockfile is a parser fixture for the exact resolved version. The
baseline CI run refreshes it with CocoaPods and records the resulting lockfile.
