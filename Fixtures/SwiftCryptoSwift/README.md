# Swift CryptoSwift consumer fixture

This repository-owned iOS 15 app compiles one Swift consumer of CryptoSwift
1.10.0. The pilot copies the fixture before installing CocoaPods, resolving
SwiftPM or building. The identical `App/Consumer.swift` must compile through
both integrations. Its SHA-256 API call is a compile-time integration probe;
the pilot does not launch the app or claim cryptographic runtime validation.

The Podfile uses modular headers, with no `use_frameworks!`. The app contains
only Swift sources. Evidence is limited to this iOS 15 Swift consumer.

The public CocoaPods specification and upstream package manifest must resolve
to the reviewed version and source revision. In particular, the pilot must
verify the expected privacy manifest in both built distributions: CocoaPods
uses a `CryptoSwift` resource bundle; SwiftPM declares a separate resources
target. A passing source build alone is insufficient for admission.

See [the 0.10 plan](../../Documentation/Plan-0.10.md). This fixture initially
runs with `--phase equivalence`, which requires both registry entries to be
absent. Registry admission requires accepted build/resource evidence, followed
by a separate `--phase migration` run on the mapped source tree.

## Pinned admission inputs

- Upstream commit: [`f2a627b84c1ff96f21ac2fcb623ab36142dd5512`](https://github.com/krzyzanowskim/CryptoSwift/tree/f2a627b84c1ff96f21ac2fcb623ab36142dd5512), dereferenced from annotated tag `1.10.0`.
- [Public CocoaPods specification](https://raw.githubusercontent.com/CocoaPods/Specs/2aec7cbaad29fecb20f77859b261ef5af3de17af/Specs/3/e/b/CryptoSwift/1.10.0/CryptoSwift.podspec.json): canonical sorted compact JSON SHA-256 `c99dec222ebbc0c4f6e0df424278e9c49b9c2ce43e89de784aff8b9f4a2d4d5f`.
- [SHA2 source](https://raw.githubusercontent.com/krzyzanowskim/CryptoSwift/f2a627b84c1ff96f21ac2fcb623ab36142dd5512/Sources/CryptoSwift/SHA2.swift): byte SHA-256 `b68697b758f4b6f4378d40df9e759e27e73ab62587299918ce68f15fd017b976`.
- [Package manifest](https://github.com/krzyzanowskim/CryptoSwift/blob/f2a627b84c1ff96f21ac2fcb623ab36142dd5512/Package.swift): product `CryptoSwift` depends on `CryptoSwiftResources` on Apple platforms.
- [Privacy manifest](https://github.com/krzyzanowskim/CryptoSwift/blob/f2a627b84c1ff96f21ac2fcb623ab36142dd5512/Sources/CryptoSwiftResources/PrivacyInfo.xcprivacy): tracking is false and the three declaration arrays are empty. The pilot compares parsed semantics in the source and named built bundles.

The required SwiftPM output path is
`CryptoSwift_CryptoSwiftResources.bundle/PrivacyInfo.xcprivacy`; its actual
presence is an acceptance check, not a claim established by manifest inspection.
