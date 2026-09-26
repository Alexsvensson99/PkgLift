# Security Policy

Security is a core consideration for PkgLift, as we operate on source code and dependency graphs.

## Supported Versions

| Version | Security support |
|---|---|
| Current `0.10.x` minor line | Supported |
| Older minor lines | Upgrade required |

## Threat Model and Mitigations

- **Malicious Podfiles**: We never execute Ruby code. Podfiles are parsed syntactically or using non-executing techniques.
- **Malicious Project Files**: We use reliable libraries like `XcodeProj` to parse project files without executing any embedded scripts or malicious payloads.
- **Plan-output paths**: Saved `.pkglift/plan.json` output requires real project/state directories and an absent or regular destination. It uses no-follow directory descriptors, checks observed bindings before publication, and replaces the plan atomically. This does not promise a filesystem transaction against another process that can rename those directories or universal power-loss recovery.
- **Registry Entries**: Normal loading and explicit registry validation check registry syntax and required non-empty fields, including repository and product fields. Those checks do not authenticate upstream repositories or prove that a product compiles for every consumer. Local overrides and configured additional paths intentionally take precedence over bundled entries, as documented in [Registry.md](Documentation/Registry.md).
- **Command Injection**: All subprocess calls (e.g., executing `swift build`) use explicit argument arrays via `ProcessRunner` and never use shell string interpretation.
- **Git URLs**: Registry URLs are treated as untrusted data and are passed to project models, never a shell.
- **Migration backups**: The exact Podfile and `.xcodeproj` are backed up before the atomic write sequence and restored if that sequence fails.

## Reporting a Vulnerability

If you discover a security vulnerability within PkgLift, please do not file a public issue.

Use GitHub's [private vulnerability reporting form](https://github.com/Alexsvensson99/PkgLift/security/advisories/new). Include the affected version or commit, impact, reproduction steps, and the smallest safe supporting material. Do not include third-party secrets, proprietary source, or unrelated personal data.

If private vulnerability reporting is temporarily unavailable, use the non-sensitive contact paths in [SUPPORT.md](SUPPORT.md) only to request a private channel. Do not place vulnerability details in a public issue. Reports are handled on a best-effort basis; acknowledgement and remediation timelines depend on severity, reproducibility, and maintainer availability.
