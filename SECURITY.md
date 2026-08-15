# Security Policy

Security is a core consideration for PkgLift, as we operate on source code and dependency graphs.

## Threat Model and Mitigations

- **Malicious Podfiles**: We never execute Ruby code. Podfiles are parsed syntactically or using non-executing techniques.
- **Malicious Project Files**: We use reliable libraries like `XcodeProj` to parse project files without executing any embedded scripts or malicious payloads.
- **Path Traversal**: We protect against symlink attacks and path traversal by validating file paths against the project root workspace.
- **Registry Entries**: All YAML registry entries are validated during normal loading and explicit registry validation. Empty/unsupported repository or product data is rejected.
- **Command Injection**: All subprocess calls (e.g., executing `swift build`) use explicit argument arrays via `ProcessRunner` and never use shell string interpretation.
- **Git URLs**: Registry URLs are treated as untrusted data and are passed to project models, never a shell.
- **Migration backups**: The exact Podfile and `.xcodeproj` are backed up before the atomic write sequence and restored if that sequence fails.

## Reporting a Vulnerability

If you discover a security vulnerability within PkgLift, please do not file a public issue.

Instead, please send an e-mail to the maintainers (or use GitHub Security Advisories). We will respond promptly.
