# Pinned Real-Project Pilots

PkgLift uses a small set of public Xcode projects to complement synthetic fixtures. Each pilot is pinned to an exact commit and has an explicit expected safety outcome. The purpose is to reveal real project shapes and migration boundaries without changing upstream repositories or treating every refusal as a defect.

## Read-only pilot matrix

The `Pinned Pilots` workflow performs these phases:

1. builds the current PkgLift source in release mode;
2. creates an isolated, detached partial checkout of the exact upstream commit, uses cone-mode sparse checkout for a nested pilot root, and rejects any canonical root that resolves outside that checkout;
3. runs `analyze` and records JSON output;
4. generates and validates a migration plan;
5. runs the migration dry run;
6. proves that tracked files, the index, and visible untracked files remain unchanged;
7. checks project-specific expected classifications;
8. summarizes stable classification reason-code counts; and
9. uploads only portable-JSON analysis and plan output plus path-redacted dry-run, environment, source, and summary files; full executable JSON remains outside the uploaded artifact.

The read-only matrix does **not** run `pod install`, execute upstream scripts, apply a migration, push to the upstream repository, or receive repository secrets.

| Case | Repository and pinned commit | Verified outcome | Tracking |
|---|---|---|---|
| Positive | `aws-samples/amazon-ivs-grid-feed-for-ios-demo` at `5573a57d4cb7e10f7ad86f95c548ddfbeabc6e1d` | `SDWebImage` is `AUTO`; `AmazonIVSPlayer` remains non-automatic | #23 |
| Mixed | `ayseyurek/LoodosCase` at `407b65db02469467b3317ca8dee0d8676c7e673e` | Alamofire, Kingfisher, and the newly mapped `lottie-ios 3.2.2` are `AUTO`; the older `Firebase/RemoteConfig` is `REVIEW`, while other unsupported identities remain non-automatic | #24 |
| Conservative | `Finb/V2ex-Swift` at `28ef39d2e5fc11d28bc79743ba2bc5f5594ba170` | dynamic Ruby and `post_install` force a mutation-free refusal; no direct entry becomes `AUTO` | #25 |
| Tinode compatibility | `tinode/ios` at `a4db1251549c40b7aa4f269cd79234eb4c07baff` | 11 direct identities; dynamic Ruby and `post_install` keep every entry non-automatic | local batch `20260815` |
| Broad mixed catalog | `devMEremenko/XcodeBenchmark` at `60d82d23e34fd63c4cae5d26d10cbdd88f0b0ee2` | 42 direct identities; `MagicalRecord` proves unpinned Git provenance while `RxBluetoothKit` proves that a tag without a full checkout commit remains incomplete; neither becomes `AUTO` | #53 |
| Objective-C/macOS shape | `Hammerspoon/hammerspoon` at `23e387e2805a9890066366e0ac96c71b27f0cfd5` | 10 direct identities; `CocoaHTTPServer` proves unpinned Git provenance while `Sentry` proves that a tag without a full checkout commit remains incomplete; neither becomes `AUTO` | #53 |
| Nested example root | `vtourraine/AcknowList` at `0288baabb859af22b9e152555fa56b56094de789` under `Examples/AcknowExampleCocoaPods` | the local `AcknowList` pod remains `BLOCKED` | local batch `20260815` |
| Parenthesized CocoaPods example | `fastlane/fastlane` at `a9a72554e1f4d6658842d4f3a7b0ca236b5c1589` under `gym/examples/cocoapods` | literal `target('Example')` and `pod("HexColors")` are attributed exactly; the unmapped dependency remains `UNKNOWN` | #48 |
| Project-only FirebaseUI example | `firebase/FirebaseUI-iOS` at `c30af73fee50724dcd9a3acf70548d3e58c86dc7` under `samples/swift` | explicit project selection works without a workspace; local pods remain blocked and `Firebase/Auth` remains `REVIEW` without complete version/project evidence | #48 |
| Legacy Firebase Auth Quickstart | `firebase/snippets-ios` at `affc6b838d3dc3382ca741983dad489631d52b43` under `qs-snippets/LegacyAuthQuickstart` | direct Firebase mappings are found but remain `REVIEW` because top-level attribution and `use_frameworks!` prevent `AUTO` | #48 |

Hammerspoon and XcodeBenchmark independently exercise literal external Git sources at pinned public commits. Each case requires matching analysis and plan provenance plus stable reason codes for an unpinned dependency and an incomplete tagged dependency; both also require a complete no-`AUTO` result. The fastlane case directly exercises parenthesized literal syntax. FirebaseUI and the Legacy Auth Quickstart exercise explicit project-without-workspace selection and conservative refusal. No pilot expectation treats source provenance or a new registry mapping alone as sufficient for `AUTO`.

## Repository-owned mixed-language end-to-end pilot

Only `Fixtures/MixedLanguageSDWebImage` may be changed by the end-to-end workflow. It is owned by this repository and contains one iOS target with both a Swift source and an Objective-C source importing SDWebImage. Upstream pilot repositories are never passed to `migrate --apply`.

The `Mixed-Language End-to-End Pilot` workflow uses two disposable copies:

1. a baseline copy runs `pod install --clean-install`, verifies `SDWebImage 5.18.1`, and builds both consumers for a generic iOS Simulator destination;
2. a separate copy records hashes for the two source files and one resource before dependency tooling runs;
3. PkgLift analysis must report a complete `swift` plus `objectiveC` target profile and the complete reviewed `AUTO` set must equal only `SDWebImage`;
4. a deterministic whole-tree hash proves that `migrate` dry-run changed nothing;
5. only that repository-owned copy reaches `migrate --apply`;
6. CocoaPods refreshes the now-empty Podfile, then `pkglift verify --build` resolves SwiftPM and builds the generated workspace;
7. the protected source and resource hashes must remain identical.

The workflow receives no secrets and has only `contents: read`. Code signing is disabled, external commands have process-group timeouts, and artifacts contain selected reports and hashes rather than source files.

The v0.2.0 Amazon IVS migration remains historical release evidence:

- Successful workflow: https://github.com/Alexsvensson99/PkgLift/actions/runs/31860034938
- Implementation: PR #34
- Verification defect found by the pilot and fixed before completion: #35 / PR #36

In v0.2.1 and later, that upstream repository remains in the read-only matrix only. The end-to-end apply boundary is the repository-owned fixture, regardless of an upstream project's license or apparent classification.

## Upstream source and licensing

The pilots are external projects. Their upstream repositories, histories, and licenses remain authoritative.

- The Amazon IVS sample reports an MIT No Attribution (`MIT-0`) license.
- V2ex-Swift reports an MIT license.
- Tinode, FirebaseUI, and Firebase snippets report Apache-2.0 licenses.
- XcodeBenchmark, Hammerspoon, AcknowList, and fastlane report MIT licenses.
- No license file was detected for LoodosCase at the pinned commit. Its checkout is therefore used only transiently for analysis, no source is copied into PkgLift, and no upstream source is uploaded as an artifact. Replace this pilot if its use ever requires redistribution or a broader right than transient validation.

A pilot update must change the recorded commit explicitly, explain why the old commit is no longer sufficient, and review the new Podfile, lockfile, project shape, license, and expected result.

## Running the workflows

The pilot gates and their underlying validation run on every pull request and main-branch push. This intentionally spends more runner time so a pull request cannot modify a path filter and receive a green gate for skipped work. The complete read-only matrix also runs weekly to detect pinned-upstream or Xcode-runner drift. Maintainers can start either workflow manually from GitHub Actions.

Each job writes a Markdown summary with deterministic direct-dependency classifications and reason-code occurrence counts, then keeps its selected validation artifact for 14 days. A failed job should be triaged into one of these outcomes:

- an actual PkgLift regression;
- a changed or incorrect expectation in the harness;
- an unsupported but safe project shape;
- an external network or upstream availability failure;
- a focused fixture, diagnostic, registry, or documentation improvement tracked through the report-to-reproduction workflow.

Do not weaken an exact-mapping, version, target, clean-worktree, or Podfile safety gate merely to make a pilot pass.
