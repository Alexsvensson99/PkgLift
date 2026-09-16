# PkgLift 0.10 plan: verified CryptoSwift migration

Status: implementation and full migration accepted in [PR #114](https://github.com/Alexsvensson99/PkgLift/pull/114); release preparation is underway. No 0.10 release is published.
The baseline is public 0.9.0 plus its final documentation at
`88a265fe4270fddf94e760c9aaf29f8630c71ba7`.

## Scope

Admit the exact `CryptoSwift` CocoaPods identity and SwiftPM product only after
concrete evidence for the 1.10.0 boundary. Initial support is limited to the
repository-owned Swift-only iOS 15 consumer. Track the work in
[issue #59](https://github.com/Alexsvensson99/PkgLift/issues/59).

SwiftSoup's version boundary (#57) and DGCharts' repository/product identity
(#56) remain separate research candidates. They are not acceptance criteria
or promised mappings for 0.10. Generated packages, broader source selection,
additional platforms/languages and changes to `AUTO` safety are outside scope.
The 1.0 quality bar in the roadmap remains the long-term target.

## Acceptance sequence

1. Bind the public CocoaPods specification, exact source tag/revision, package
   product, source bytes and privacy-manifest semantics to immutable evidence.
2. With both registry copies absent, build identical consumer bytes through
   CocoaPods and SwiftPM. Verify the public-spec/lock checksum and exact resolved
   package pin. Require the expected privacy resource in each built output.
3. Only after admission passes, add matching schema-2 registry copies restricted
   to Swift and iOS 15. Prove exact lookup plus conservative refusal for earlier
   versions, subspecs, mixed languages and unsupported platform evidence.
4. Run Analyze → Plan → dry run → Apply → Verify with a full consumer build.
   Preserve the app's source, remove only the exact pod declaration, check the
   resolved package revision and privacy resources, and prove dry run is inert.
5. Pass build, full Swift tests, registry validation, helper regressions, the
   existing pilot suite and CodeQL on the reviewed change.
6. Prepare release notes and a concrete publication proposal after integration.
   Public signing, tag/release and Homebrew distribution remain the separate
   release workflow; the binary version is not changed by the admission pilot.

If identity, build or resource evidence conflicts, keep CryptoSwift unmapped
and document the precise blocker. Never weaken a guard to make a pilot pass.

## Accepted feature baseline

PR #114 merged as `7cd328696e6eb15824e7ec9db40a9e1cebdf3bc3` after all 23
checks passed on reviewed head `8d9a971616749a068d9d0012228c4540d0bf4c58`.
The pre-mapping admission and full migration evidence are recorded in
[verified consumer mappings](VerifiedConsumerMappings.md#cryptoswift-admission-for-010-unreleased).
Release-candidate checks, private signed distribution acceptance and publication
are separate from this completed feature evidence.
