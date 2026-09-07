import Darwin
import Foundation
import PkgLiftSignalSupport

/// One apply owns signals for the executable's lifetime. During mutation the
/// handler records a flag; after successful finish a delayed handler can exit.
final class MigrationSignals {
    init() throws {
        let result = pkglift_signals_install()
        guard result == 0 else { throw SignalError.installationFailed(result) }
    }

    func checkCancellation() throws {
        if let interruption = capturedInterruption() { throw interruption }
        try Task.checkCancellation()
    }

    func capturedInterruption() -> MigrationInterrupted? {
        let signal = pkglift_signals_received()
        return signal == 0 ? nil : MigrationInterrupted(signal: signal)
    }

    func finish(succeeded: Bool) throws -> MigrationInterrupted? {
        var signal: Int32 = 0
        let result = pkglift_signals_finish(succeeded ? 1 : 0, &signal)
        guard result == 0 else { throw SignalError.restorationFailed(result) }
        return signal == 0 ? nil : MigrationInterrupted(signal: signal)
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
