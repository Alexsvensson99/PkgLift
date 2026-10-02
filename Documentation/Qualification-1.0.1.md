# PkgLift 1.0.1 qualification

Status: **published on 2026-10-02 Europe/Stockholm**. GitHub published
[PkgLift v1.0.1](https://github.com/Alexsvensson99/PkgLift/releases/tag/v1.0.1)
at `2026-10-01T23:31:14Z`. Tag `v1.0.1` targets manifest commit M,
`030b8a21d936a96e76090ca39ac78dd68c4df51c`, and the public archive matches
the signed candidate accepted before publication.

This record keeps source qualification, signed-candidate acceptance, public
distribution and Homebrew qualification as separate gates. The retained
portable receipts are the authoritative machine-readable record:

- [source qualification](Evidence/Qualification-1.0.1/source-qualification.json)
- [cloud signed-M acceptance](Evidence/Qualification-1.0.1/cloud-final-M-acceptance.json)
- [local signed-M acceptance](Evidence/Qualification-1.0.1/local-final-M-acceptance.json)
- [public distribution](Evidence/Qualification-1.0.1/public-distribution.json)

## Candidate identity

| State | Identity and relationship |
| --- | --- |
| Final source F | `76dd1f9712f9e5da3609bacc26e0d0022e2ae290`, prepared by [PR #142](https://github.com/Alexsvensson99/PkgLift/pull/142), merged at `2026-09-30T19:20:18Z`. |
| Source qualification | The [main pilot](https://github.com/Alexsvensson99/PkgLift/actions/runs/36764966069) and [G3 qualification](https://github.com/Alexsvensson99/PkgLift/actions/runs/36765095908) both passed on exact F. |
| Manifest M | `030b8a21d936a96e76090ca39ac78dd68c4df51c`, prepared by [PR #143](https://github.com/Alexsvensson99/PkgLift/pull/143), merged at `2026-09-30T20:00:22Z`. M has F as its sole parent and changes only `.github/releases/v1.0.1.json`. |
| Public release | Release ID `401431070`; lightweight tag `v1.0.1` targets exact M; draft `false`; prerelease `false`. |

The manifest binds F, PR #142 and successful main pilot run `36764966069`.
The later signed and public checks bind their results to M and do not replace
the source evidence from F.

## Gate result

| Gate | Result and boundary |
| --- | --- |
| F protected source qualification | Passed. All 30 reported checks succeeded. The local tree-matched preparation passed 422 XCTest plus 233 Swift Testing tests, 300 release-policy tests, 25 registry mappings and an unchanged six-module public API comparison. |
| F external G3 qualification | Passed in run `36765095908`, attempt 1. AWS Grid Feed built before and after a partial SDWebImage 5.18.1 migration while AmazonIVSPlayer 1.40.0 remained under CocoaPods. FirebaseUI and Hammerspoon passed mutation-protected refusal cases. |
| M protected checks | Passed. Fresh final readback showed all 30 reported M checks successful, including protected publication run `36769590339`. |
| Signed and notarized M | Passed in [release run 36769614583](https://github.com/Alexsvensson99/PkgLift/actions/runs/36769614583), attempt 1. Package/sign/notarize, hosted consumer acceptance and the macOS 14 runtime job all succeeded. |
| Local exact-M acceptance | Passed against the same archive on macOS 27/Xcode 27: core runtime, PartialSwift, PartialMixed, PartialSwiftCoexistence and full mixed-language migration/build. This is local, non-GitHub-hosted evidence. |
| Protected publication and public readback | Passed. Publication run `36769590339` completed successfully; the tag, release metadata, two assets, signature, version, bundled registry and downloaded hashes were read back from the public release. |
| Homebrew | Passed. [PR #18](https://github.com/Alexsvensson99/homebrew-tap/pull/18) merged as `0f1faf8805b00c575f1989075235b3609c89a7ea`. [PR CI 36942357174](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36942357174) and [main CI 36942559400](https://github.com/Alexsvensson99/homebrew-tap/actions/runs/36942559400), both attempt 1, passed all eight required lifecycle steps. Local syntax, style and diff checks passed; no local install or audit was performed for 1.0.1. |

## Accepted artifact identity

| Artifact | SHA-256 |
| --- | --- |
| `pkglift-macos-arm64.tar.gz` | `eaee546af04f11df66d1f16cbbbf66dea881969e0dd34795d1a5b74e65b9e591` |
| Extracted `pkglift` binary | `b7409899d57ed6e90c4afaa11c46e29da85a889eb5ec7028189191c2c4cb8173` |
| Registry bundle tree | `14e6d8975c87f7ad88b6d92bd43319662db9a43893f134ca0000abf0234e5510` |

The public archive has asset ID `604351908`, size `3696851` bytes and provider
digest `sha256:eaee546af04f11df66d1f16cbbbf66dea881969e0dd34795d1a5b74e65b9e591`.
The public checksum file has asset ID `604351906`, size `93` bytes and provider
digest `sha256:ba4767986d16eea416843d9a486a0a5b59333a00c0fdfc50801a6c0ec20cb111`.
The public release body SHA-256 is
`41484414afa64ab7ee28ef66af810b8d6bca10dcf327409651cfdf9e85f758db`
and matches the reviewed publication proposal.
Strict signature verification, `pkglift version` returning `1.0.1`, and bundled
registry validation of 25 mappings all passed on the downloaded public bytes.

## Environment and workload evidence

Each row contains only observations captured by that job or local execution.
Missing fields are not borrowed from another row.

| Evidence cell | Observed environment | Workload and result |
| --- | --- | --- |
| F source and G3 | G3: macOS 15.7.9, arm64; Xcode 16.4; Swift 6.1.2; CocoaPods 1.17.0 | Main pilot run `36764966069` and G3 run `36765095908` passed on F. G3 covered the named AWS partial migration and two refusal cases. The source qualification receipt separately binds the 655 local Swift tests, 300 policy tests and unchanged six-module API comparison to the tree reused by F. |
| Signed-M hosted consumers | macOS 15.7.9 (24G830), arm64; image `macos15` / `20260907.0337.1`; Xcode 16.4 (16F6); Swift 6.1.2 (`swiftlang-6.1.2.1.2`); CocoaPods 1.17.0; iOS Simulator SDK 18.5 (22F76); macOS SDK 15.5 (24F74) | Full mixed migration/build, PartialMixed migration/build retaining KeychainAccess, and protected-source/index-preserving Hammerspoon refusal passed. Planning may add `.pkglift/plan.json`; the subsequent dry run was mutation-free. |
| Signed-M macOS 14 runtime | macOS 14.8.9 (23J631), arm64; image `macos14` / `20260831.0302.1` | Signature/quarantine, version, registry, analyze, plan, dry run and structural apply passed. No consumer build ran in this cell. |
| Signed-M local consumers | macOS 27.0 (26A428), arm64; Xcode 27.0 (27A266a); Swift 6.4 (`swiftlang-6.4.0.34.1`); CocoaPods 1.17.0; iOS Simulator SDK 27.0 (24A430); macOS SDK 27.0 (26A425); no runner image | Core runtime and four consumer flows passed using exact M bytes. Consumer builds used Debug/arm64 and iOS deployment target 15.0. |

## Compatibility boundary

XcodeProj 9.17.5 changes a binary build input, so the 1.0.0 signed-binary
acceptance could not qualify 1.0.1. The new exact-M cloud and local acceptance
closes that maintenance-release gate. The six public Swift library products
compare unchanged, preserving the documented 1.x source contract.

The update fails closed on unsupported `.xcproj` definitions, including bundles
that also contain a PBX definition. It does not add JSON-project migration.
Saved analysis and executable plans must be regenerated with 1.0.1 before dry
run or apply.

These environment rows are independent observations. They do not define a
continuous Xcode range, establish exact macOS 14.0 runtime support, or add a
positive external multi-target/workspace migration case. That external
positive cell remains deferred; discovery, explicit selection and conservative
refusal retain their existing boundaries.

The complete 1.0.0 qualification remains an immutable historical record in
[Qualification-1.0.md](Qualification-1.0.md).
