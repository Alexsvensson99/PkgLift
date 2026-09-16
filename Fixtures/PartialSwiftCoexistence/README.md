# Partial migration with existing SwiftPM

Repository-owned Swift iOS 15 consumer with three dependency roles:

- DeviceKit 5.8.0 is already linked through SwiftPM and used by `Consumer.swift`.
- KeychainAccess 4.2.2 starts on CocoaPods and migrates to SwiftPM.
- SDWebImage 5.18.1 stays on CocoaPods through the explicit migration deny policy.

The scheme remains `SwiftKeychainAccess`. Run `Scripts/run-partial-migration-pilot.py`
with `--case PartialSwiftCoexistence` as documented in
[partial migration qualification](../../Documentation/PartialMigration-1.0.md).
The pilot requires baseline and fresh migrated builds, exact package pins,
unchanged existing DeviceKit project objects, and retained CocoaPods integration.
No app or simulator is launched.
