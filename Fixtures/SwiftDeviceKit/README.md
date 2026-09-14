# Swift DeviceKit migration fixture

This repository-owned fixture is a deliberately small iOS 15, Swift-only
application. Its one target imports `DeviceKit` through CocoaPods and compiles
`RegistryConsumer.probe()`. It is a controlled migration input: pilots must
copy it to a disposable location before running CocoaPods, PkgLift, SwiftPM
resolution, or `xcodebuild`.

The Podfile pins `DeviceKit` to `5.8.0` with modular headers and does not use
`use_frameworks!`. The project has no Objective-C sources and makes no claim
about consumer languages, targets, or platforms beyond this iOS 15 Swift
fixture.

## Upstream evidence to recheck in CI

- The [official 5.8.0 Podspec](https://github.com/devicekit/DeviceKit/blob/5.8.0/DeviceKit.podspec)
  declares the `DeviceKit` pod, version `5.8.0`, the generated source path, and
  `Source/PrivacyInfo.xcprivacy` as resource-bundle input.
- The [official SwiftPM manifest](https://github.com/devicekit/DeviceKit/blob/5.8.0/Package.swift)
  exposes the `DeviceKit` library product, excludes `Device.swift.gyb`, and
  processes `Source/PrivacyInfo.xcprivacy` as a target resource.
- The current upstream `5.8.0` annotated tag resolves to commit
  [`56b997e8a61707218f9af09f32b2a1d1806fd792`](https://github.com/devicekit/DeviceKit/tree/56b997e8a61707218f9af09f32b2a1d1806fd792).
  The checked-in generated source has Git blob ID
  `bd5a0638e16402ea1abba163e8aa2557771d1a41`.

The package and pod declarations reference the same privacy-manifest source
path, but canonical output equivalence is intentionally unproven here. CI must
resolve both dependency paths, compile this consumer, and inspect the built
resource output before treating the privacy manifest as equivalent.
