# PartialMixed partial migration fixture

Repository-owned derivative of `MixedLanguageSDWebImage`. It pins two genuine
registry dependencies: `SDWebImage` 5.18.1 is the reviewed AUTO migration,
while `KeychainAccess` 4.2.2 remains on CocoaPods because the fixture's
`.pkglift.yml` explicitly denies its migration. The deny policy makes
KeychainAccess BLOCKED without changing registry evidence. Its Swift-only
consumer-language evidence also does not cover this target's complete Swift and
Objective-C source profile.

The mixed target continues to import SDWebImage from both Swift and Objective-C.
Its Swift `AppDelegate` also calls the retained KeychainAccess API, so the final
build must contain a functioning SwiftPM product and a functioning CocoaPods
product in the same target. The pilot builds the app but never launches it.

Run `Scripts/run-partial-migration-pilot.py --case PartialMixed --output /absolute/new/output --pkglift /absolute/path/to/pkglift` from the repository root. The runner works on a fresh disposable copy, validates the exact baseline, dry run, apply, CocoaPods refresh, linkage and final build. No app or simulator is launched.
