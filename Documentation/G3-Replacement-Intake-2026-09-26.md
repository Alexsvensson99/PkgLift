# G3 replacement search intake — 2026-09-26

Status: **no qualifying replacement found; G3 remains open.**

This is a bounded, authorized, read-only public-source search status record. It
does not classify an upstream dependency as `AUTO`, authorize an upstream
checkout, install CocoaPods, run a build, or establish a qualification result.

## Scope and method

The search looked for a new positive multi-target consumer following the
documented ZBNetworking header-import refusal. A suitable future candidate must
have an immutable source revision, a recognized license, committed `Podfile` and
`Podfile.lock`, a registry-supported locked dependency, two or more native
targets (an app plus a native test target is sufficient), and a simple,
literal, reviewed target mapping. Global framework mode, dynamic Ruby,
unreviewed source-rewriting hooks, inherited target ambiguity, and external Git
provenance were conservative screening exclusions for this search. The main
SDWebImage screen required a lock version at least 5.1.0; SDWebImage is not a
general requirement for G3, as the Swift-oriented cross-check below demonstrates.

Authenticated public GitHub code search was used after local candidate evidence
had been reviewed. The following commands returned the listed number of items:

| Query | Returned items |
|---|---:|
| `SDWebImage filename:Podfile` | 100 |
| `SDWebImage 5.18 filename:Podfile` | 100 |
| `SDWebImage 5.19 filename:Podfile` | 100 |
| `SDWebImage 5.20 filename:Podfile` | 100 |
| `SDWebImage filename:Podfile -use_frameworks -post_install -inherit` | 0 |
| `SDWebImage filename:Podfile -use_frameworks` | 0 |
| `SDWebImage filename:Podfile -post_install` | 0 |
| `SDWebImage filename:Podfile -inherit` | 0 |

These are query-response counts capped by `--limit 100`, not unique-project or
exhaustive-result totals. GitHub's `filename:Podfile` search also returned
`Podfile.lock` paths for version searches. A zero result records GitHub's search
response for that exact qualifier expression; it does not prove a property of
every possible public repository. Direct immutable files were read before any
candidate-specific conclusion.

## Closest screened source shapes

None is an execution intake.

| Source revision | SDWebImage / shape | Exclusion |
|---|---|---|
| [StepicOrg/stepik-ios `5fc20cc`](https://github.com/StepicOrg/stepik-ios/blob/5fc20cc066d85916ffb7126e3b918a31b80afdb0/Podfile) | 5.19.7; iOS 12; app/test shape | Global `use_frameworks!`, nested `inherit!`, and `post_install`. |
| [RedrockMobile/CyxbsMobile_iOS `ecda29c`](https://github.com/RedrockMobile/CyxbsMobile_iOS/blob/ecda29c63b025c73f557b768c3e87c2ac1d587ea/Podfile) | Locked 5.x; app plus widget extension | Global framework mode and `post_install`. |
| [TempTalkOrg/TempTalk-iOS `c47c3db`](https://github.com/TempTalkOrg/TempTalk-iOS/blob/c47c3db839fe2290f4e016df33bab9e783bd05ce/Podfile) | `~> 5.0`; app plus Share and notification extensions | Global framework mode, inherited targets, and a large post-install mutation. |
| [ExistOrLive/GithubClient `7969212`](https://github.com/ExistOrLive/GithubClient/blob/7969212a8b6c938f93391d6e37666cc2c4a4c207/ZLGitHubClient/Podfile) | Locked 5.19.1; iOS 12; app plus extension | Post-install mutates signing, deployment and source; several Git-sourced pods. |
| [QuintGao/GKPhotoBrowser `a4cff78`](https://github.com/QuintGao/GKPhotoBrowser/blob/a4cff78675b348421f30f1901ce3befe077745f7/GKPhotoBrowserDemo/Podfile) | MIT; locked 5.21.2; mixed Objective-C/Swift iOS 10 source | Mapped Podfile target uses `use_frameworks!` and a source/project-mutating post-install hook. Its Objective-C consumer import is module-qualified: [`CustomWebImageManager.m`](https://github.com/QuintGao/GKPhotoBrowser/blob/a4cff78675b348421f30f1901ce3befe077745f7/GKPhotoBrowserDemo/GKPhotoBrowserDemo/Classes/Main/Custom/CustomWebImageManager.m). |

Other bounded candidates either locked SDWebImage below 5.1.0, lacked a usable
committed Podfile/lock pair, had fewer than two native targets, or contained the
same excluded constructs. No source header scan was treated as sufficient to
override a structural exclusion.

## DeviceKit cross-check

A separate Swift-oriented screen used `pod "DeviceKit" filename:Podfile` with
`--limit 30`: GitHub returned 30 items and 25 Podfiles were read after skipping
the already screened Stepic entry, synthetic paths and non-Podfile entries. Those numbers include duplicates and are not
unique-project or viable-candidate counts. All actual external DeviceKit
declarations in that bounded screen used framework mode. For example,
[AppliedRecognition/Ver-ID-UI-iOS `6551fe7`](https://github.com/AppliedRecognition/Ver-ID-UI-iOS/blob/6551fe705de5b07d16a2500a856922680b917889/Podfile)
declares DeviceKit `~> 5.5` with `use_frameworks!` and `post_install`; and
[wavesplatform/WavesWallet-iOS `6826c34`](https://github.com/wavesplatform/WavesWallet-iOS/blob/6826c342feda13a010b5d3c5a9ebc1fadfbc3fa7/Podfile)
has multi-target DeviceKit declarations but global framework mode, inherited
targets and `post_install`.

The apparent exceptions were not candidates: PkgLift's own SwiftDeviceKit
fixture is out of scope, Tuya's `ThingSmartAppleDeviceKit` is a false positive,
and `pxx917144686/iDevice_ZH` mentions DeviceKit only in a comment. This
cross-check adds no positive G3 replacement.

## Relationship to the existing G3 evidence

ZBNetworking remains a conservative regression case. Its flat
`#import <SDImageCache.h>` is documented as requiring REVIEW, rather than as a
successful migration, in [MultiTargetQualification-1.0.md](MultiTargetQualification-1.0.md#diagnosed-consumer-header-import-blocker).
The associated local evidence explicitly records `g3Closed: false`, no applied
migration, no new hosted run and no release:
[zb-header-import-review.json](Evidence/MultiTargetQualification-1.0/zb-header-import-review.json).

## Fail-closed next direction

Do not substitute a near miss or reinterpret this search as a qualification.
For a next bounded screen, prioritize recent Objective-C apps with module-qualified
SDWebImage imports and simple app/test targets. The Swift-oriented searches
repeatedly reached framework mode. Before a candidate advances to execution
intake, check: a license; committed literal Podfile and
lockfile; a lock version supported by the registry; an app plus native test or
extension target; no global framework mode, dynamic mutation, unreviewed
post-install hook, or external Git dependency; and source imports suitable for
the current header-import inspector. These search exclusions do not change the
classifier or imply that every excluded shape is intrinsically unsafe. Supporting
a currently refused shape requires a separately scoped, evidence-backed change.
For a candidate that passes, create a separate reviewed
execution intake that binds source and file hashes, target mapping, expected
complete classifications, and generated-Pods preparation. Only an analysis from
the current executable and a later authorized qualification can establish a
positive G3 result.
