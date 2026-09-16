# Verified consumer mapping admission

A registry mapping is admitted only after a repository-owned consumer compiles
through both CocoaPods and Swift Package Manager (SwiftPM). The two admitted
0.9.0 mappings below use deliberately small Swift-only iOS 15 apps:

| CocoaPods pod / SwiftPM product | CocoaPods version | SwiftPM repository | reviewed revision | canonical public podspec SHA-256 | reviewed source SHA-256 |
| --- | --- | --- | --- | --- | --- |
| KeychainAccess / KeychainAccess | 4.2.2 | `https://github.com/kishikawakatsumi/KeychainAccess` | `84e546727d66f1adc5439debad16270d0fdd04e7` | `4ce03eee844a5d98600f81b6284cb17968005d0504e4a7a5b86ad4f4e87cbc48` | `643188af53d8dbecddd3de1a6e6888ea801d1bc4f022138a4a56a6aea0e7a274` (`Lib/KeychainAccess/Keychain.swift`) |
| DeviceKit / DeviceKit | 5.8.0 | `https://github.com/devicekit/DeviceKit` | `56b997e8a61707218f9af09f32b2a1d1806fd792` | `87970b1f51a445b9d1e22b4cca1f8c2a7b70bafbb4ed8cd46d2c98691cfa43a8` | `025d97e3d3071b1b7a080a4ed6b22d342a57aa872454a8ad389b51f8c27b3ad5` (`Source/Device.generated.swift`) |

The podspec digests are SHA-256 values of parsed public JSON rendered by the
pilot as sorted, compact JSON. They are not CocoaPods lockfile checksums. The
immutable primary sources are the [KeychainAccess 4.2.2 CocoaPods
spec](https://raw.githubusercontent.com/CocoaPods/Specs/79116babc7079cdce2f90f34adbb2667532e637d/Specs/f/6/3/KeychainAccess/4.2.2/KeychainAccess.podspec.json)
and [DeviceKit 5.8.0 CocoaPods
spec](https://raw.githubusercontent.com/CocoaPods/Specs/d9713efb46e5742f0817e67905d465f429c579c2/Specs/d/e/6/DeviceKit/5.8.0/DeviceKit.podspec.json).

The owned inputs are [SwiftKeychainAccess](../Fixtures/SwiftKeychainAccess/)
and [SwiftDeviceKit](../Fixtures/SwiftDeviceKit/). Each uses one iOS 15 app
target and a package-specific `App/Consumer.swift`. The CocoaPods baseline is
configured to compile that file. Before any registry mapping exists, the pilot
copies its bytes unchanged into a standalone iOS 15 SwiftPM library consumer
and builds that second integration. A passing pair proves only the listed Swift
consumer source, product, exact version, and the iOS 15 environment.

`Scripts/run-registry-consumer-pilot.py` obtains the public podspec and installs
the copied fixture with CocoaPods. It locates the actual registry specification
with `pod spec which <pod> --version=<version> --no-ansi`, requiring one regular
JSON file. Its raw SHA-1 must equal the one `SPEC CHECKSUMS` binding for that
pod in the generated `Podfile.lock`, and its complete parsed JSON must equal
the pinned public reference above. This intentionally does not treat a
`Pods/Local Podspecs` copy or a hand-authored checksum as registry evidence.

The pilot then resolves and builds the standalone SwiftPM consumer, requiring
one exact `Package.resolved` pin for the reviewed repository, version, and
revision, plus a matching checkout-source digest. The repository fixture is
hashed before and after the disposable copies run. See each fixture README for
its API probe and upstream context:
[KeychainAccess](../Fixtures/SwiftKeychainAccess/README.md) and
[DeviceKit](../Fixtures/SwiftDeviceKit/README.md).

The schema-2 source and bundled mappings were introduced only after the
pre-mapping admission below. Their full migration remains mandatory recurring
`Registry Gate` coverage in [PR 110 checks](https://github.com/Alexsvensson99/PkgLift/pull/110/checks):
it runs a fresh CocoaPods input through analyze and plan, requires exactly one
AUTO candidate for that pod, verifies the product, Swift-only source profile,
and iOS 15 platform evidence, performs dry run and apply, and finishes with
`pkglift verify --build`. It rechecks the resolved SwiftPM pin and checkout
source after migration. Read the exact reviewed head and current migration
result from those PR checks rather than from this document.

For DeviceKit, the pilot also compares the parsed `PrivacyInfo.xcprivacy`
semantics in the CocoaPods and SwiftPM-built outputs against the reviewed
manifest. This is resource-presence and resource-content evidence for the
built consumers. It is not a runtime privacy test or a legal/privacy-policy
claim. Likewise, the KeychainAccess consumer is compiled as an API probe;
its Keychain calls are not executed during the build, so it is not runtime
keychain-I/O evidence.

## Compatibility and refusal rules

Platform constraints live in registry schema 2. Schema 2 requires a non-empty,
duplicate-free `swiftpm.supportedConsumerPlatforms` list with strict deployment
targets. Schema 1 must omit that field and retains its legacy behavior. The
version split makes an older PkgLift reject a constrained mapping instead of
silently ignoring a new field. Current classification and migration preflight
also fail closed if a programmatically supplied mapping violates that contract.

The evidence here does not authorize broad platform or language claims:

- `use_frameworks!` remains REVIEW.
- A mixed-language target remains REVIEW unless every source language has
  concrete mapping evidence.
- An unmapped subspec remains UNKNOWN.
- A target on an unlisted platform, or with missing, invalid, or too-low
  deployment evidence, remains REVIEW.

## Pre-mapping admission evidence

Both equivalence proofs passed in GitHub Actions
[run 34901842976](https://github.com/Alexsvensson99/PkgLift/actions/runs/34901842976)
for source head [`0cf48d8cf850697c546f6341bfe13a6875507feb`](https://github.com/Alexsvensson99/PkgLift/commit/0cf48d8cf850697c546f6341bfe13a6875507feb)
and CI merge [`fa7231b57af7e010be6f07aa19bc1910ca7709e0`](https://github.com/Alexsvensson99/PkgLift/commit/fa7231b57af7e010be6f07aa19bc1910ca7709e0).
Each admission record confirms that the mapping was absent at proof time, the
full resolved registry podspec matched the pinned public JSON, both consumer
builds passed, the exact SwiftPM pin and checkout source matched, and the owned
fixture stayed unchanged.

| Candidate | Consumer SHA-256 | DeviceKit built-resource evidence | CI evidence |
| --- | --- | --- | --- |
| KeychainAccess 4.2.2 | `6e4c63960d2901f97a105c951541260b7b06882f5475bfb3c6e55fbd8eab3801` | not applicable | [job 104170379315](https://github.com/Alexsvensson99/PkgLift/actions/runs/34901842976/job/104170379315), [artifact 10371327585](https://github.com/Alexsvensson99/PkgLift/actions/runs/34901842976/artifacts/10371327585) |
| DeviceKit 5.8.0 | `9068f311f156bb7817484926db25463970ac314b6104ca03ec4a44c5e38ddf65` | CocoaPods `DeviceKit.bundle/PrivacyInfo.xcprivacy`; SwiftPM `DeviceKit_DeviceKit.bundle/PrivacyInfo.xcprivacy` | [job 104170379302](https://github.com/Alexsvensson99/PkgLift/actions/runs/34901842976/job/104170379302), [artifact 10370563966](https://github.com/Alexsvensson99/PkgLift/actions/runs/34901842976/artifacts/10370563966) |

These are admission records for the pre-mapping integrations. They do not
replace the separate migration and verification evidence required by the
Registry Gate.

## CryptoSwift admission for 0.10 (unreleased)

CryptoSwift 1.10.0 passed its pre-mapping admission in
[run 35050169615](https://github.com/Alexsvensson99/PkgLift/actions/runs/35050169615)
at reviewed head `44a76770e12a1a4db4ab158e02d24d857291a699` and CI merge
`d55bb2c8d71f7bf42576e5092de89e1b2fa82a47`. Both registry copies were absent.
The [consumer job](https://github.com/Alexsvensson99/PkgLift/actions/runs/35050169615/job/104649455779)
and [artifact 10429390145](https://github.com/Alexsvensson99/PkgLift/actions/runs/35050169615/artifacts/10429390145)
record successful CocoaPods and SwiftPM builds of identical Swift iOS 15
consumer bytes. The fixture was unchanged.

- Reviewed upstream revision: `f2a627b84c1ff96f21ac2fcb623ab36142dd5512`.
- Consumer SHA-256: `fe353216f0cddb4b61a28d43c6e3bc4ca689fda676c8b32fe3b2308a49032932`.
- Canonical public podspec SHA-256: `c99dec222ebbc0c4f6e0df424278e9c49b9c2ce43e89de784aff8b9f4a2d4d5f`.
- Source inventory SHA-256: `10c2d15bc4b07f919095ceabf2c2de246264a367ef8fb2c1b1d01171e0166dba`.
- Observed CocoaPods privacy output: `CryptoSwift.bundle/PrivacyInfo.xcprivacy`.
- Observed SwiftPM privacy output: `CryptoSwift_CryptoSwiftResources.bundle/PrivacyInfo.xcprivacy`.

Unlike the earlier sentinel-only source checks, this pilot binds all 113 core
Swift source files to Git blob identities from the reviewed revision, rejecting
changed, missing or additional compiled files. CocoaPods must match this complete
compiled-source inventory plus privacy bytes; SwiftPM must also match the
manifest and resource-target source. This binds relevant source contents even
when CocoaPods does not retain a Git checkout. The built resources must contain
the reviewed privacy semantics; missing or unrelated resources cannot satisfy
the guard. This is build evidence, not runtime cryptographic or privacy testing.

The schema-2 mapping preserves the existing minimum-version policy with a
`1.10.0` boundary and is limited to Swift iOS consumers targeting iOS 15 or later.
Earlier versions, unknown subspecs, unproven languages/platforms, insufficient
or missing deployment evidence, and `use_frameworks!` remain non-automatic.
See the [fixture](../Fixtures/SwiftCryptoSwift/), [issue #59](https://github.com/Alexsvensson99/PkgLift/issues/59)
and [0.10 plan](Plan-0.10.md).

The required Registry Gate now runs the complete CryptoSwift migration phase,
including fresh dual builds, reviewed plan, dry run, apply, final build, exact
resolved package and resource checks. Current migration acceptance is recorded
in [PR #114 checks](https://github.com/Alexsvensson99/PkgLift/pull/114/checks);
pre-mapping admission alone does not prove a successful migration or release.
