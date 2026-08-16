# Pinned Real-Project Pilots

PkgLift uses a small set of public Xcode projects to complement synthetic fixtures. Each pilot is pinned to an exact commit and has an explicit expected safety outcome. The purpose is to reveal real project shapes and migration boundaries without changing upstream repositories or treating every refusal as a defect.

## Read-only pilot matrix

The `Pinned Pilots` workflow performs these phases:

1. builds the current PkgLift source in release mode;
2. creates an isolated, detached checkout of the exact upstream commit;
3. runs `analyze` and records JSON output;
4. generates and validates a migration plan;
5. runs the migration dry run;
6. proves that tracked files, the index, and visible untracked files remain unchanged;
7. checks project-specific expected classifications;
8. uploads only redacted analysis, plan, dry-run, environment, source, and summary files.

The read-only matrix does **not** run `pod install`, execute upstream scripts, apply a migration, push to the upstream repository, or receive repository secrets.

| Case | Repository and pinned commit | Verified outcome | Tracking |
|---|---|---|---|
| Positive | `aws-samples/amazon-ivs-grid-feed-for-ios-demo` at `5573a57d4cb7e10f7ad86f95c548ddfbeabc6e1d` | `SDWebImage` is `AUTO`; `AmazonIVSPlayer` remains non-automatic | #23 |
| Mixed | `ayseyurek/LoodosCase` at `407b65db02469467b3317ca8dee0d8676c7e673e` | Alamofire and Kingfisher are `AUTO`; older or unmapped Firebase and Lottie identifiers remain non-automatic | #24 |
| Conservative | `Finb/V2ex-Swift` at `28ef39d2e5fc11d28bc79743ba2bc5f5594ba170` | dynamic Ruby and `post_install` force a mutation-free refusal; no direct entry becomes `AUTO` | #25 |
| Tinode compatibility | `tinode/ios` at `a4db1251549c40b7aa4f269cd79234eb4c07baff` | 11 direct identities; dynamic Ruby and `post_install` keep every entry non-automatic | local batch `20260815` |
| Broad mixed catalog | `devMEremenko/XcodeBenchmark` at `60d82d23e34fd63c4cae5d26d10cbdd88f0b0ee2` | 42 direct identities; hooks and dynamic Ruby keep every entry non-automatic | local batch `20260815` |
| Objective-C/macOS shape | `Hammerspoon/hammerspoon` at `23e387e2805a9890066366e0ac96c71b27f0cfd5` | 10 direct identities; no entry becomes `AUTO` | local batch `20260815` |
| Nested example root | `vtourraine/AcknowList` at `0288baabb859af22b9e152555fa56b56094de789` under `Examples/AcknowExampleCocoaPods` | the local `AcknowList` pod remains `BLOCKED` | local batch `20260815` |

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

Starting with v0.2.1, that upstream repository remains in the read-only matrix only. The end-to-end apply boundary is the repository-owned fixture, regardless of an upstream project's license or apparent classification.

## Upstream source and licensing

The pilots are external projects. Their upstream repositories, histories, and licenses remain authoritative.

- The Amazon IVS sample reports an MIT No Attribution (`MIT-0`) license.
- V2ex-Swift reports an MIT license.
- Tinode reports an Apache-2.0 license.
- XcodeBenchmark, Hammerspoon, and AcknowList report MIT licenses.
- No license file was detected for LoodosCase at the pinned commit. Its checkout is therefore used only transiently for analysis, no source is copied into PkgLift, and no upstream source is uploaded as an artifact. Replace this pilot if its use ever requires redistribution or a broader right than transient validation.

A pilot update must change the recorded commit explicitly, explain why the old commit is no longer sufficient, and review the new Podfile, lockfile, project shape, license, and expected result.

## Running the workflows

The read-only matrix runs on pull requests that change migration-sensitive source, registry data, or the pilot harness. The mixed-language end-to-end workflow runs only for changes that can affect its fixture, migration, verification, registry mapping, or harness. Maintainers can also start either workflow manually from GitHub Actions.

Each job writes a Markdown summary and keeps its selected validation artifact for 14 days. A failed job should be triaged into one of these outcomes:

- an actual PkgLift regression;
- a changed or incorrect expectation in the harness;
- an unsupported but safe project shape;
- an external network or upstream availability failure;
- a focused fixture, diagnostic, registry, or documentation improvement tracked through the report-to-reproduction workflow.

Do not weaken an exact-mapping, version, target, clean-worktree, or Podfile safety gate merely to make a pilot pass.
