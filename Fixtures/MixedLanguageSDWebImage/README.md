# Mixed-language migration fixture

This repository-owned iOS fixture is intentionally small. Its single target
compiles one Swift file and one Objective-C file, and both consume SDWebImage.
It exists to validate a reviewed CocoaPods-to-SwiftPM migration without ever
applying changes to an upstream project.

The end-to-end pilot copies this directory to disposable locations before
running CocoaPods, PkgLift, SwiftPM resolution, or `xcodebuild`.
