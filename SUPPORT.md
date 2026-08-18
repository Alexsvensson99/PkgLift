# PkgLift Support

PkgLift is a maintainer-led open-source project. Support is best effort and has no guaranteed response time. Please choose the narrowest public reporting path that fits the request and remove private project information first.

## Choose a path

- Use the [bug report](https://github.com/Alexsvensson99/PkgLift/issues/new?template=bug_report.md) for a reproducible defect in PkgLift.
- Use the [real-world migration report](https://github.com/Alexsvensson99/PkgLift/issues/new?template=migration_report.yml) for successful, partial, refused, or unsupported project results.
- Use the [registry mapping proposal](https://github.com/Alexsvensson99/PkgLift/issues/new?template=registry_mapping_request.yml) for an exact CocoaPods-to-SwiftPM mapping backed by official upstream evidence.
- Use the [feature request](https://github.com/Alexsvensson99/PkgLift/issues/new?template=feature_request.md) for a concrete product improvement.
- Read [Testing PkgLift on a Real Project](Documentation/RealWorldTesting.md) before opening a support report about project selection, clean-worktree refusal, planning, or verification.

Public issues must not contain tokens, credentials, private repository or dependency names, customer information, proprietary source code, signing identities, or unreviewed build logs. `pkglift diagnostics` produces a minimized local report, but you must still open and review it before sharing. Portable analyze or plan JSON can retain dependency and target names and is not a replacement for diagnostics.

## Security vulnerabilities

Do not report vulnerabilities in a public issue. Follow [SECURITY.md](SECURITY.md) and use the repository's [private vulnerability report](https://github.com/Alexsvensson99/PkgLift/security/advisories/new).

## Supported versions

Security fixes target the current `0.3.x` minor line. Older minor lines may be asked to upgrade before a defect is investigated. Source builds from unreviewed branches and modified registry entries are supported only when the report includes enough reproducible evidence to distinguish local changes from a PkgLift defect.
