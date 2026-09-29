# Registry evidence ledger for PkgLift 1.0

Reviewed 2026-09-29 against the 25 bundled mappings on the 1.0 qualification
branch. This ledger records what the repository can prove about each mapping;
it does not change a mapping or classification by itself.

## Evidence contract

The registry's `minimumVersion` remains a conservative lower boundary. An
official tag at that boundary establishes that the named CocoaPods identity,
SwiftPM repository and product exist together. A compiled candidate at one
exact version records an observed compatibility cell; it does not turn the
threshold policy into an exact-version allowlist and does not claim that every
later version was built.

Evidence is separated into three layers:

- **U (upstream mapping evidence):** an official tagged podspec and package
  manifest establish the CocoaPods identity, repository, product and upstream
  platform metadata.
- **C (compiled consumer evidence):** a repository-owned fixture or a pinned
  public project has compiled the relevant CocoaPods and SwiftPM forms in the
  stated language/platform/version cell.
- **R (read-only project evidence):** a pinned project exercised discovery,
  classification or refusal without dependency installation or a build. This
  proves the classifier boundary, not consumer compatibility.

Schema 1 has no `supportedConsumerPlatforms` field. Its age and omission are
not, by themselves, a defect: the documented legacy policy intentionally keeps
the existing behavior. Consequently, an upstream podspec's platform list is
recorded below as source metadata, not as a new registry platform claim. New
executable mappings use schema 2 and require concrete consumer-language and
platform evidence.

## Official source sets

These exact-tag sources are shared by multiple rows in the matrix.

- **AF-5.0.0:** [podspec](https://github.com/Alamofire/Alamofire/blob/5.0.0/Alamofire.podspec),
  [manifest](https://github.com/Alamofire/Alamofire/blob/5.0.0/Package.swift).
  Both name `Alamofire`; the podspec declares Swift 5 and iOS 10/macOS 10.12/
  tvOS 10/watchOS 3, matching the manifest's product and platform declarations.
- **KF-5.15.8:** [podspec](https://github.com/onevcat/Kingfisher/blob/5.15.8/Kingfisher.podspec),
  [manifest](https://github.com/onevcat/Kingfisher/blob/5.15.8/Package.swift).
  Both name the `Kingfisher` product; the podspec describes a pure-Swift
  implementation and declares Swift 4/4.2/5 plus iOS 10/macOS 10.12/tvOS 10/
  watchOS 3.
- **LOT-3.2.2:** [podspec](https://github.com/airbnb/lottie-ios/blob/3.2.2/lottie-ios.podspec),
  [manifest](https://github.com/airbnb/lottie-ios/blob/3.2.2/Package.swift).
  The pod is `lottie-ios`, the SwiftPM product is `Lottie`, and the tagged
  sources declare Swift 5. The manifest declares iOS 9; the podspec additionally
  declares macOS 10.10 and tvOS 9.
- **MOYA-14.0.0:** [podspec](https://github.com/Moya/Moya/blob/14.0.0/Moya.podspec),
  [manifest](https://github.com/Moya/Moya/blob/14.0.0/Package.swift).
  Both expose `Moya`; the podspec declares Swift 5 and iOS 10/macOS 10.12/
  tvOS 10/watchOS 3.
- **SD-5.1.0:** [podspec](https://github.com/SDWebImage/SDWebImage/blob/5.1.0/SDWebImage.podspec),
  [manifest](https://github.com/SDWebImage/SDWebImage/blob/5.1.0/Package.swift).
  Both expose `SDWebImage`; the tagged package compiles Objective-C sources and
  declares iOS 8/macOS 10.10/tvOS 9/watchOS 2.
- **SENTRY-7.0.0:** [podspec](https://github.com/getsentry/sentry-cocoa/blob/7.0.0/Sentry.podspec),
  [manifest](https://github.com/getsentry/sentry-cocoa/blob/7.0.0/Package.swift).
  Both expose `Sentry`; the manifest includes the public Objective-C headers and
  a Swift test target and declares iOS 9/macOS 10.10/tvOS 9/watchOS 2.
- **SNAP-5.0.0:** [podspec](https://github.com/SnapKit/SnapKit/blob/5.0.0/SnapKit.podspec),
  [manifest](https://github.com/SnapKit/SnapKit/blob/5.0.0/Package.swift).
  Both expose `SnapKit`; the podspec binds Swift 5 source and declares iOS 10,
  macOS 10.12 and tvOS 10. The tagged manifest does not declare package
  platforms, so the podspec values are upstream CocoaPods metadata only.
- **SJ-5.0.0:** [podspec](https://github.com/SwiftyJSON/SwiftyJSON/blob/5.0.0/SwiftyJSON.podspec),
  [manifest](https://github.com/SwiftyJSON/SwiftyJSON/blob/5.0.0/Package.swift).
  Both expose `SwiftyJSON`; the manifest declares Swift 5 and iOS 8/macOS 10.10/
  tvOS 9/watchOS 3.
- **FB-8.0.0:** [umbrella podspec](https://github.com/firebase/firebase-ios-sdk/blob/8.0.0/Firebase.podspec),
  [manifest](https://github.com/firebase/firebase-ios-sdk/blob/8.0.0/Package.swift).
  The podspec defines the exact `Firebase/*` subspecs and dependencies; the
  manifest exports their matching SwiftPM products.
- **FB-11.12.0:** [umbrella podspec](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/Firebase.podspec),
  [manifest](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/Package.swift),
  and direct podspecs for [Analytics](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/FirebaseAnalytics.podspec),
  [Auth](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/FirebaseAuth.podspec),
  [Crashlytics](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/FirebaseCrashlytics.podspec),
  [Firestore](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/FirebaseFirestore.podspec),
  [Messaging](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/FirebaseMessaging.podspec),
  [Remote Config](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/FirebaseRemoteConfig.podspec),
  and [Storage](https://github.com/firebase/firebase-ios-sdk/blob/11.12.0/FirebaseStorage.podspec).
  These exact-tag files establish the direct and umbrella identities, product
  names and per-component deployment metadata. The manifest also contains
  Swift and Objective-C API test targets, but those upstream tests are not a
  substitute for a PkgLift-owned dual-language migration consumer.
- **KA-4.2.2:** immutable [CocoaPods specification](https://raw.githubusercontent.com/CocoaPods/Specs/79116babc7079cdce2f90f34adbb2667532e637d/Specs/f/6/3/KeychainAccess/4.2.2/KeychainAccess.podspec.json)
  and [manifest at the dereferenced tag commit](https://raw.githubusercontent.com/kishikawakatsumi/KeychainAccess/84e546727d66f1adc5439debad16270d0fdd04e7/Package.swift).
- **DK-5.8.0:** official [podspec](https://github.com/devicekit/DeviceKit/blob/5.8.0/DeviceKit.podspec)
  and [manifest](https://github.com/devicekit/DeviceKit/blob/5.8.0/Package.swift).
- **CS-1.10.0:** immutable [CocoaPods specification](https://raw.githubusercontent.com/CocoaPods/Specs/2aec7cbaad29fecb20f77859b261ef5af3de17af/Specs/3/e/b/CryptoSwift/1.10.0/CryptoSwift.podspec.json)
  and [manifest at the dereferenced tag commit](https://github.com/krzyzanowskim/CryptoSwift/blob/f2a627b84c1ff96f21ac2fcb623ab36142dd5512/Package.swift).
  The complete-source/resource checks and dual-build results for all three are
  recorded in [Verified consumer mapping admission](VerifiedConsumerMappings.md)
  and the [KeychainAccess](../Fixtures/SwiftKeychainAccess/README.md),
  [DeviceKit](../Fixtures/SwiftDeviceKit/README.md), and
  [CryptoSwift](../Fixtures/SwiftCryptoSwift/README.md) fixture records.

## 25-row ledger

`Gap` means evidence required by the current contribution contract is not linked
in this repository. It does not mean the upstream package is incompatible.
Dates are each mapping's current `metadata.lastVerified` value.

| CocoaPods identity -> SwiftPM product | Schema / boundary / languages | Official evidence | Repository evidence | Finding and minimum justified follow-up |
| --- | --- | --- | --- | --- |
| `Alamofire` -> `Alamofire` | 1 / 5.0.0 / Swift; 2026-08-14 | AF-5.0.0 | R: Loodos classifies it `AUTO`; no build. A separate 5.10.2 source-inspection case refuses unsupported selection and is not consumer evidence. | Identity, product, boundary and Swift implementation are substantiated. Gap: no linked compiling consumer for the declared consumer language. Recover an archived build receipt or add one focused Swift consumer before calling this row consumer-admitted. |
| `CryptoSwift` -> `CryptoSwift` | 2 / 1.10.0 / Swift / iOS 15; 2026-09-16 | CS-1.10.0 | C: CocoaPods and SwiftPM consumers, all 113 compiled Swift sources, privacy resource and full migration are bound at 1.10.0/iOS 15. | Complete for its declared cell. Later versions remain governed by the existing threshold policy and other live AUTO gates. |
| `DeviceKit` -> `DeviceKit` | 2 / 5.8.0 / Swift / iOS 15; 2026-09-15 | DK-5.8.0 | C: dual consumer builds, generated source/privacy resource checks and recurring full migration; an existing SwiftPM pin also survives partial migration. | Complete for its declared cell. |
| `Firebase/Analytics` -> `FirebaseAnalytics` | 1 / 8.0.0 / Swift+Objective-C; 2026-08-14 | FB-8.0.0 | No compiled PkgLift consumer linked. | Identity/product are substantiated. Gap: the two-language consumer claim lacks linked repository-owned compilation. |
| `FirebaseAnalytics` -> `FirebaseAnalytics` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 Analytics podspec + manifest | R: direct Firebase mappings appear in refusal pilots; no build. | Identity/product are substantiated. Gap: no linked dual-language PkgLift consumer. |
| `Firebase/Auth` -> `FirebaseAuth` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 umbrella Auth subspec + manifest | R: FirebaseUI stays `REVIEW` without complete version/project evidence; no build. | The refusal is correct but does not admit the mapping. Gap: no linked dual-language consumer. |
| `FirebaseAuth` -> `FirebaseAuth` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 Auth podspec + manifest | R: Legacy Auth Quickstart finds direct mappings but remains `REVIEW` under attribution and `use_frameworks!`; no build. | Identity/product are substantiated. Gap: no linked dual-language consumer. |
| `Firebase/Crashlytics` -> `FirebaseCrashlytics` | 1 / 8.0.0 / Swift+Objective-C; 2026-08-14 | FB-8.0.0 | No compiled PkgLift consumer linked. | Identity/product are substantiated. Gap: no linked dual-language consumer. |
| `FirebaseCrashlytics` -> `FirebaseCrashlytics` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 Crashlytics podspec + manifest | R: Firebase refusal coverage only; no build. | Identity/product are substantiated. Gap: no linked dual-language consumer. |
| `Firebase/Firestore` -> `FirebaseFirestore` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 umbrella Firestore subspec + manifest | R: catalog/refusal coverage only; no build. | Identity/product are substantiated. Gap: no linked dual-language consumer. |
| `FirebaseFirestore` -> `FirebaseFirestore` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 Firestore podspec + manifest | R: catalog/refusal coverage only; no build. | Identity/product are substantiated. Gap: no linked dual-language consumer. |
| `Firebase/Messaging` -> `FirebaseMessaging` | 1 / 8.0.0 / Swift+Objective-C; 2026-08-14 | FB-8.0.0 | No compiled PkgLift consumer linked. | Identity/product are substantiated. Gap: no linked dual-language consumer. |
| `FirebaseMessaging` -> `FirebaseMessaging` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 Messaging podspec + manifest | R: Firebase refusal coverage only; no build. | Identity/product are substantiated. Gap: no linked dual-language consumer. |
| `Firebase/RemoteConfig` -> `FirebaseRemoteConfig` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 umbrella RemoteConfig subspec + manifest | R: the older Loodos lock resolves below the boundary and remains `REVIEW`; no build. | Boundary refusal is evidenced. Gap: no linked dual-language consumer at or above 11.12.0. |
| `FirebaseRemoteConfig` -> `FirebaseRemoteConfig` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 Remote Config podspec + manifest | R: Firebase refusal coverage only; no build. | Identity/product are substantiated. Gap: no linked dual-language consumer. |
| `Firebase/Storage` -> `FirebaseStorage` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 umbrella Storage subspec + manifest | R: Firebase refusal coverage only; no build. | Identity/product are substantiated. Gap: no linked dual-language consumer. |
| `FirebaseStorage` -> `FirebaseStorage` | 1 / 11.12.0 / Swift+Objective-C; 2026-08-16 | FB-11.12.0 Storage podspec + manifest | R: Firebase refusal coverage only; no build. | Identity/product are substantiated. Gap: no linked dual-language consumer. |
| `KeychainAccess` -> `KeychainAccess` | 2 / 4.2.2 / Swift / iOS 15; 2026-09-15 | KA-4.2.2 | C: dual consumer admission, recurring Registry Gate and full/partial migration builds at 4.2.2/iOS 15. | Complete for its declared cell. |
| `Kingfisher` -> `Kingfisher` | 1 / 5.15.8 / Swift; 2026-08-14 | KF-5.15.8 | R: Loodos classifies it `AUTO`; no build. | Identity, product, boundary and Swift implementation are substantiated. Gap: no linked compiling consumer. |
| `lottie-ios` -> `Lottie` | 1 / 3.2.2 / Swift; 2026-08-16 | LOT-3.2.2 | R: Loodos classifies it `AUTO`; no build. | Identity, renamed product, boundary and Swift implementation are substantiated. Gap: no linked compiling consumer. |
| `Moya` -> `Moya` | 1 / 14.0.0 / Swift; 2026-08-14 | MOYA-14.0.0 | No project or compiled consumer evidence linked. | Identity, product, boundary and Swift implementation are substantiated. Gap: add the smallest reproducible Swift consumer build. |
| `SDWebImage` -> `SDWebImage` | 1 / 5.1.0 / Swift+Objective-C; 2026-08-14 | SD-5.1.0 | C: repository-owned mixed-language full migration and pinned AWS full partial migration build at 5.18.1/iOS 15. The source-only AWS and current ZB cases correctly remain `REVIEW`; PartialMixed also compiles both languages at 5.18.1. | The declared languages have concrete 5.18.1/iOS 15 evidence. This does not claim every version from 5.1.0 onward was built or add a schema-1 platform constraint. |
| `Sentry` -> `Sentry` | 1 / 7.0.0 / Swift+Objective-C; 2026-08-14 | SENTRY-7.0.0 | R: Hammerspoon records `external_git_evidence_incomplete`; no build. | Identity/product and upstream mixed-language surface are substantiated. Gap: no linked dual-language PkgLift consumer. |
| `SnapKit` -> `SnapKit` | 1 / 5.0.0 / Swift; 2026-08-14 | SNAP-5.0.0 | Source inspection at 5.7.1 binds 37 files/bytes but explicitly does not prove buildability or migration. | Identity, product, boundary and Swift implementation are substantiated. Gap: no linked compiling consumer; do not promote source inspection to build evidence. |
| `SwiftyJSON` -> `SwiftyJSON` | 1 / 5.0.0 / Swift; 2026-08-14 | SJ-5.0.0 | No project or compiled consumer evidence linked. | Identity, product, boundary and Swift implementation are substantiated. Gap: add the smallest reproducible Swift consumer build. |

The count is therefore 25 mappings with official mapping evidence, four with
repository-linked compiled consumer evidence (three schema-2 admissions plus
SDWebImage), and 21 without such compiled evidence. Read-only classification,
refusal and source-byte inspection remain useful safety evidence but do not fill
the consumer-build gap.

## Concrete documentation and intake findings

1. `Documentation/ReleaseNotes-0.3.0.md` calls Lottie and the added Firebase
   identities "verified ... consumer boundary" mappings. The current repository
   links official tagged mapping evidence and read-only/refusal pilots, but no
   compiled consumer receipt for those rows. Close this by linking a recoverable
   archived receipt/fixture, or qualify that historical wording; the ledger does
   not assume the upstream mapping is wrong.
2. `Documentation/Registry.md` accurately describes current configured language
   claims but previously gave no per-row source/build distinction. This ledger
   supplies that distinction without changing the `minimumVersion` contract.
3. The registry request form asked for consumer languages and language evidence
   but omitted required platform, deployment-target and platform-evidence fields.
   The form now collects the values required for a schema-2 executable mapping.

No upstream identity, SwiftPM product, repository URL or recorded minimum-version
boundary was contradicted during this audit. The audit therefore does not establish a mapping defect requiring automatic
eligibility to change. The stricter compiling-consumer admission requirement
applies to new mappings; it is not retroactively inferred solely from schema age.
Legacy mappings retain their existing evidence-based threshold policy, with
compiled qualification explicitly limited to the observed cells. Any future
restriction must identify a concrete unsupported claim or independently adopted
policy change; it must not replace `minimumVersion` with an exact-version-only
catalog as an incidental G5 fix.

## Local evidence references

- [Pinned read-only pilots](Pilots.md)
- [Verified consumer mapping admission](VerifiedConsumerMappings.md)
- [Partial migration qualification](PartialMigration-1.0.md)
- [Real-project qualification](RealProjectQualification-1.0.md)
- [Multi-target qualification](MultiTargetQualification-1.0.md)
- [Local source-inspection validation](LocalSourceInspection-0.8-Validation.md)
