// PkgLiftCore/ExitCode.swift
// Defines predictable, documented exit codes for PkgLift CLI.

import Foundation

/// Documented exit codes for the PkgLift CLI.
///
/// These codes are stable across versions and suitable for scripting.
///
/// | Code | Meaning |
/// |------|---------|
/// | 0 | Success |
/// | 1 | General error |
/// | 2 | Invalid project or input |
/// | 3 | Migration blocked |
/// | 4 | Verification failed |
/// | 5 | Unsafe working tree |
/// | 6 | Registry validation failed |
public enum PkgLiftExitCode: Int32, Sendable {
    case success = 0
    case generalError = 1
    case invalidInput = 2
    case migrationBlocked = 3
    case verificationFailed = 4
    case unsafeWorkingTree = 5
    case registryValidationFailed = 6
}
