# PartialSwift partial migration fixture

Repository-owned derivative of `SwiftKeychainAccess`. It pins two genuine
registry dependencies: `KeychainAccess` 4.2.2 is the reviewed AUTO migration,
while `SDWebImage` 5.18.1 remains on CocoaPods because the fixture's
`.pkglift.yml` explicitly denies its migration. The deny policy changes only
`SDWebImage` to BLOCKED; it does not add or weaken registry evidence for either
dependency.

The Swift consumer imports both dependencies. `RegistryConsumer` exercises the
KeychainAccess API, and `AppDelegate` calls `SDImageCache.clearMemory` so the
retained CocoaPods product must still compile and link after the partial
migration. The pilot builds the app but never launches it.

Run `Scripts/run-partial-migration-pilot.py --case PartialSwift --output /absolute/new/output --pkglift /absolute/path/to/pkglift` from the repository root. The runner works on a fresh disposable copy, validates the exact baseline, dry run, apply, CocoaPods refresh, linkage and final build. No app or simulator is launched.
