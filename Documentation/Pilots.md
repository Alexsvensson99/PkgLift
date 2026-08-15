# Pinned Real-Project Pilots

PkgLift uses a small set of public Xcode projects to complement synthetic fixtures. Each pilot is pinned to an exact commit and has an explicit expected safety outcome. The purpose is to reveal real project shapes and migration boundaries without changing upstream repositories or treating every refusal as a defect.

## Automated scope

The `Pinned Pilots` workflow currently performs these phases:

1. builds the current PkgLift source in release mode;
2. creates an isolated, detached checkout of the exact upstream commit;
3. runs `analyze` and records JSON output;
4. generates and validates a migration plan;
5. runs the migration dry run;
6. proves that tracked files, the index, and visible untracked files remain unchanged;
7. checks project-specific expected classifications;
8. uploads only redacted analysis, plan, dry-run, environment, source, and summary files.

The workflow does **not** run `pod install`, execute upstream scripts, apply a migration, push to the upstream repository, or receive repository secrets. Apply and build validation require a separately reviewed follow-up because old public projects can depend on unavailable services, credentials, or obsolete toolchains.

## Pilot matrix

| Case | Repository and pinned commit | Expected outcome | Tracking |
|---|---|---|---|
| Positive | `aws-samples/amazon-ivs-grid-feed-for-ios-demo` at `5573a57d4cb7e10f7ad86f95c548ddfbeabc6e1d` | `SDWebImage` is eligible for `AUTO`; `AmazonIVSPlayer` remains non-automatic | #23 |
| Mixed | `ayseyurek/LoodosCase` at `407b65db02469467b3317ca8dee0d8676c7e673e` | Alamofire and Kingfisher may be `AUTO`; older or unmapped Firebase and Lottie identifiers remain non-automatic | #24 |
| Conservative | `Finb/V2ex-Swift` at `28ef39d2e5fc11d28bc79743ba2bc5f5594ba170` | dynamic Ruby and `post_install` force a mutation-free refusal; no direct entry becomes `AUTO` | #25 |

## Upstream source and licensing

The pilots are external projects. Their upstream repositories, histories, and licenses remain authoritative.

- The Amazon IVS sample reports an MIT No Attribution (`MIT-0`) license.
- V2ex-Swift reports an MIT license.
- No license file was detected for LoodosCase at the pinned commit. Its checkout is therefore used only transiently for analysis, no source is copied into PkgLift, and no upstream source is uploaded as an artifact. Replace this pilot if its use ever requires redistribution or a broader right than transient validation.

A pilot update must change the recorded commit explicitly, explain why the old commit is no longer sufficient, and review the new Podfile, lockfile, project shape, and expected result.

## Running the workflow

The workflow runs on pull requests that change migration-sensitive source, registry data, or the pilot harness. Maintainers can also start it manually from GitHub Actions.

Each matrix job writes a Markdown summary and uploads a redacted artifact for 14 days. A failed job should be triaged into one of these outcomes:

- an actual PkgLift regression;
- a changed or incorrect expectation in the harness;
- an unsupported but safe project shape;
- an external network or upstream availability failure;
- a focused fixture, diagnostic, registry, or documentation improvement tracked through #13.

Do not weaken an exact-mapping, version, target, clean-worktree, or Podfile safety gate merely to make a pilot pass.
