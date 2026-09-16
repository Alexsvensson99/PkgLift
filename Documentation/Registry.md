# Dependency Registry

The registry maps a CocoaPod identifier to a verified SwiftPM repository and one or more package products. Entries are YAML files under `Registry/` and in the bundled registry resource.

```yaml
schemaVersion: 1
pod:
  name: Alamofire
swiftpm:
  repository: https://github.com/Alamofire/Alamofire
  products:
    - Alamofire
  minimumVersion: 5.0.0
  supportedConsumerLanguages:
    - swift
migration:
  confidence: verified
metadata:
  notes: Official mapping
  lastVerified: "2026-08-14"
```

Subspec mappings add `pod.subspec`. Identifiers are exact: a base pod mapping never applies automatically to an undeclared subspec.

`swiftpm.minimumVersion` records a conservative upstream tag where the repository and listed products were verified. It must use stable `major.minor.patch` form. It is compared with the exact version resolved by `Podfile.lock`; it is never used to invent or upgrade a project version. Schema-1 mappings that omit the field remain load-compatible but are `REVIEW`-only.

`swiftpm.supportedConsumerLanguages` records the Xcode target languages for which the exact package and product mapping has concrete consumer evidence. Allowed values are `swift`, `objectiveC`, `objectiveCPlusPlus`, `c`, and `cPlusPlus`. A mixed target requires every detected language. New executable mappings must use a non-empty, duplicate-free list; empty, duplicate, or unknown values fail validation. Older external schema-1 mappings without this field remain readable but are `REVIEW`-only.

`swiftpm.supportedConsumerPlatforms` narrows a mapping to consumer environments with concrete build evidence. Constrained mappings use schema version 2 so clients that predate this field reject the mapping instead of silently ignoring its safety boundary. Schema 2 requires a present, non-empty list; schema 1 rejects the field and remains the unchanged legacy format. Each entry uses one canonical platform (`iOS`, `macOS`, `tvOS`, `watchOS`, or `visionOS`) and a quoted, strict numeric `minimumDeploymentTarget` string with one to three components:

```yaml
schemaVersion: 2
pod:
  name: PodName
swiftpm:
  repository: https://github.com/org/repo
  products: [ProductName]
  minimumVersion: 1.0.0
  supportedConsumerLanguages: [swift]
  supportedConsumerPlatforms:
    - platform: iOS
      minimumDeploymentTarget: "15.0"
migration:
  confidence: verified
```

The list must contain each platform at most once and use valid deployment versions. The analyzed target must resolve to one listed platform and a deployment target greater than or equal to the recorded minimum across every build configuration; missing, ambiguous, malformed, unlisted, or lower target evidence produces `REVIEW`, and migration preflight checks the live target again before mutation. Existing schema-1 mappings without this field retain their prior behavior. New executable mappings must use schema 2 with concrete platform evidence and focused refusal tests.

The bundled registry records Swift support for Alamofire, Kingfisher, Lottie, Moya, SnapKit, and SwiftyJSON, and Swift plus Objective-C support for the mapped Firebase identities, SDWebImage, and Sentry. KeychainAccess 4.2.2 and DeviceKit 5.8.0 add schema-2 mappings restricted to Swift consumers targeting iOS 15 or later. Their [consumer build evidence](VerifiedConsumerMappings.md) precedes registry admission; the CI Registry Gate also requires full migration and build verification. The unreleased 0.10 work adds CryptoSwift at the verified 1.10.0 minimum-version boundary under the same Swift/iOS 15 constraints, after separate complete-source and built-resource admission.

`lottie-ios` maps exactly to the `Lottie` product from `https://github.com/airbnb/lottie-ios`, verified from `3.2.2` against the [upstream manifest](https://github.com/airbnb/lottie-ios/blob/3.2.2/Package.swift).

The following direct Firebase identities are independently mapped at `11.12.0`: `FirebaseAnalytics`, `FirebaseAuth`, `FirebaseCrashlytics`, `FirebaseFirestore`, `FirebaseMessaging`, `FirebaseRemoteConfig`, and `FirebaseStorage`. The exact `Firebase/Analytics`, `Firebase/Auth`, `Firebase/Firestore`, `Firebase/RemoteConfig`, and `Firebase/Storage` subspec mappings remain separate identities, with the four newly added subspecs verified at `11.12.0`. Evidence comes from the exact-tag [Package.swift](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/Package.swift) and [Firebase.podspec](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/Firebase.podspec).

There is no base-to-subspec fallback. `Firebase`, `Firebase/Core`, unknown subspecs, and nested identities such as `Firebase/Auth/Extra` remain unmapped unless a separate exact registry entry is reviewed and added.

## Validation

Normal analysis validates every loaded entry, including local overrides, before classification. Invalid URLs, empty products, malformed minimum versions, invalid consumer-language lists, unsupported schema versions, malformed YAML, or a configured registry path that is missing or not a directory stop loading before bundled mappings can be used.

Run the full registry validation explicitly with:

```bash
swift run pkglift registry validate
```

Resolution precedence is:

1. `.pkglift/registry/` local overrides;
2. paths listed in `.pkglift.yml` under `registry.additionalPaths`;
3. the bundled registry.

The first exact pod/subspec identifier at the highest-precedence source wins.
