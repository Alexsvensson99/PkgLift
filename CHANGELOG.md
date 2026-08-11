# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased
### Added
- Core `analyze`, `plan`, `migrate`, and `verify` commands.
- Static Podfile parser (no Ruby execution required).
- Xcode project manipulation via `XcodeProj`.
- Foundation for the Dependency Registry.
- Auto/Review/Blocked/Unknown classification system.
- Safe, atomized migration strategies.

### Changed
- AUTO plans now contain executable, typed remove-package-link actions.
- Migration preflight refuses missing versions, missing/ambiguous targets, stale action metadata, and conflicting existing package requirements before mutation.
- Podfile editing preserves target blocks and unrelated Ruby during partial migration.
- Git safety explicitly supports clean, dirty, and non-Git projects.
- Verification checks package-product-target linkage.
