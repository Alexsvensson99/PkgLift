# Pinned Real-Project Pilots

PkgLift uses a small set of public Xcode projects to complement synthetic fixtures. Each pilot is pinned to an exact commit and has an explicit expected safety outcome. The purpose is to reveal real project shapes and migration boundaries without changing upstream repositories or treating every refusal as a defect.

## Read-only pilot matrix

The `Pinned Pilots` workflow currently performs these phases:

1. builds the current PkgLift source in release mode;
2. creates an isolated, detached checkout of the exact upstream commit;
3. runs `analyze` and records JSON output;
4. generates and validates a migration plan;
5. runs the migration dry run;
6. proves that tracked files, the index, and visible untracked files remain unchanged;
7. checks project-specific expected classifications;
8. uploads only redacted analysis, plan, dry-run, environment, source, and summary files.

The read-only matrix does **not** run `pod install`, execute upstream scripts, apply a migration, push to the upstream repository, or receive repository secrets.

| Case | Repository and pinned commit | Expected outcome | Tracking |
|---|---|---|---|
| Positive | `aws-samples/amazon-ivs-grid-feed-for-ios-demo` at `5573a57d4cb7e10f7ad86f95c548ddfbeabc6e1d` | `SDWebImage` is eligible for `AUTO`; `AmazonIVSPlayer` remains non-automatic | #23 |
| Mixed | `ayseyurek/LoodosCase` at `407b65db02469467b3317ca8dee0d8676c7e673e` | Alamofire and Kingfisher may be `AUTO`; older or unmapped Firebase and Lottie identifiers remain non-automatic | #24 |
| Conservative | `Finb/V2ex-Swift` at `28ef39d2e5fc11d28bc79743ba2bc5f5594ba170` | dynamic Ruby and `post_install` force a mutation-free refusal; no direct entry becomes `AUTO` | #25 |

## Positive end-to-end pilot

The Amazon IVS sample is also covered by a separate `Positive End-to-End Pilot` workflow because its pinned source is MIT-0 licensed and its Podfile has no install hooks or dynamic Ruby.

The end-to-end workflow uses two isolated checkouts:

1. a baseline checkout runs `pod install --deployment` and an iOS Simulator build;
2. a separate clean checkout runs PkgLift analysis, plan validation, and dry run;
3. only the reviewed `SDWebImage` `AUTO` action is applied;
4. CocoaPods refreshes the remaining `AmazonIVSPlayer` dependency;
5. `pkglift verify --build` resolves SwiftPM and builds the migrated workspace;
6. the final diff is restricted to dependency configuration files, and source or resource changes fail the job.

The workflow receives no secrets and has only `contents: read`. It cannot push to the upstream repository. Build execution occurs only on an ephemeral GitHub-hosted runner, with code signing disabled. Artifacts contain the summary and dependency-validation output, not the upstream source tree.

The end-to-end job is intentionally limited to the positive licensed pilot. The mixed pilot has no detected license file at its pinned commit and therefore remains transient read-only analysis. The conservative pilot contains dynamic Ruby and an install hook; applying it would contradict the expected safe refusal.

## Upstream source and licensing

The pilots are external projects. Their upstream repositories, histories, and licenses remain authoritative.

- The Amazon IVS sample reports an MIT No Attribution (`MIT-0`) license.
- V2ex-Swift reports an MIT license.
- No license file was detected for LoodosCase at the pinned commit. Its checkout is therefore used only transiently for analysis, no source is copied into PkgLift, and no upstream source is uploaded as an artifact. Replace this pilot if its use ever requires redistribution or a broader right than transient validation.

A pilot update must change the recorded commit explicitly, explain why the old commit is no longer sufficient, and review the new Podfile, lockfile, project shape, and expected result.

## Running the workflows

The read-only matrix runs on pull requests that change migration-sensitive source, registry data, or the pilot harness. The positive end-to-end workflow runs only for changes that can affect its migration, verification, registry mapping, or harness. Maintainers can also start either workflow manually from GitHub Actions.

Each job writes a Markdown summary and keeps its selected validation artifact for 14 days. A failed job should be triaged into one of these outcomes:

- an actual PkgLift regression;
- a changed or incorrect expectation in the harness;
- an unsupported but safe project shape;
- an external network or upstream availability failure;
- a focused fixture, diagnostic, registry, or documentation improvement tracked through #13.

Do not weaken an exact-mapping, version, target, clean-worktree, or Podfile safety gate merely to make a pilot pass.
