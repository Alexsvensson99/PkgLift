// PkgLiftCore/ExitCode.swift
// Legacy numeric exit-code catalogue exposed by the Core library.

import Foundation

/// Legacy numeric codes retained for library source compatibility.
///
/// The CLI does not map its errors through this enum. In particular, cases
/// 2...6 are not a promise of emitted process statuses. Consult
/// Documentation/Compatibility-1.0.md for the actual CLI exit contract.
/// Preserve these case names and raw values for existing library clients.
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
