// PkgLiftCore/ProcessRunner.swift
// Safe external process execution.

import Foundation

// MARK: - Process Runner

/// Safely executes external processes with explicit argument arrays.
///
/// ## Security
///
/// - Never builds shell commands by concatenating untrusted strings
/// - Uses `Process` with explicit argument arrays
/// - Avoids `/bin/sh -c` unless absolutely unavoidable
/// - Treats all repository input as untrusted
public struct ProcessRunner: Sendable {
    public init() {}

    /// Run an external process and capture output.
    ///
    /// - Parameters:
    ///   - executable: Path to the executable.
    ///   - arguments: Explicit argument array (never shell-interpolated).
    ///   - workingDirectory: Working directory for the process.
    ///   - environment: Additional environment variables.
    /// - Returns: Process result with exit code and output.
    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        if let environment = environment {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                env[key] = value
            }
            process.environment = env
        }

        // Capture to private temporary files so a verbose child process cannot
        // deadlock after filling an unread pipe while this synchronous API is
        // waiting for termination.
        let captureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgLiftProcess-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: captureDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: captureDirectory) }
        let stdoutURL = captureDirectory.appendingPathComponent("stdout")
        let stderrURL = captureDirectory.appendingPathComponent("stderr")
        guard FileManager.default.createFile(atPath: stdoutURL.path, contents: nil),
              FileManager.default.createFile(atPath: stderrURL.path, contents: nil) else {
            throw ProcessRunnerError.captureSetupFailed
        }
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()
        try stdoutHandle.close()
        try stderrHandle.close()

        let stdoutData = try Data(contentsOf: stdoutURL)
        let stderrData = try Data(contentsOf: stderrURL)

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    /// Check if an executable exists at the given path or in PATH.
    public func executableExists(_ name: String) -> Bool {
        // Check absolute path
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name)
        }

        // Check in PATH
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
            return false
        }

        for directory in pathEnv.split(separator: ":") {
            let fullPath = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return true
            }
        }

        return false
    }

    /// Find the full path of an executable.
    public func findExecutable(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }

        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
            return nil
        }

        for directory in pathEnv.split(separator: ":") {
            let fullPath = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return nil
    }
}

public enum ProcessRunnerError: LocalizedError, Sendable {
    case captureSetupFailed

    public var errorDescription: String? {
        switch self {
        case .captureSetupFailed:
            return "Unable to create private files for process output capture."
        }
    }
}

// MARK: - Process Result

/// Result of an external process execution.
public struct ProcessResult: Sendable {
    /// Process exit code.
    public let exitCode: Int32

    /// Standard output.
    public let stdout: String

    /// Standard error.
    public let stderr: String

    /// Whether the process succeeded (exit code 0).
    public var succeeded: Bool {
        exitCode == 0
    }

    /// Trimmed standard output.
    public var trimmedStdout: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
