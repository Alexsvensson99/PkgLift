import Darwin
import Foundation
import PkgLiftSignalSupport

/// Owns process signal dispositions only for the synchronous apply/rollback
/// scope. The C handler records a flag; checkpoints throw on the normal stack.
final class MigrationSignals {
    init() throws {
        let result = pkglift_signals_install()
        guard result == 0 else { throw SignalError.installationFailed(result) }
    }

    func checkCancellation() throws {
        let signal = pkglift_signals_received()
        if signal != 0 { throw MigrationInterrupted(signal: signal) }
        try Task.checkCancellation()
    }

    func restore() throws {
        let result = pkglift_signals_restore()
        guard result == 0 else { throw SignalError.restorationFailed(result) }
    }

    enum SignalError: LocalizedError {
        case installationFailed(Int32)
        case restorationFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .installationFailed(let code):
                return "Could not install migration signal handlers (errno \(code)). No migration started."
            case .restorationFailed(let code):
                return "Could not restore process signal handlers (errno \(code))."
            }
        }
    }
}

struct MigrationInterrupted: LocalizedError {
    let signal: Int32

    var errorDescription: String? {
        "Migration interrupted by \(signal == SIGINT ? "SIGINT" : "SIGTERM")."
    }

    var exitCode: Int32 { 128 + signal }
}
