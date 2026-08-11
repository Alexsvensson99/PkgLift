// PkgLiftCore/Diagnostics.swift
// Consistent diagnostic output system for PkgLift.

import Foundation

// MARK: - Diagnostic Level

/// Severity levels for diagnostic messages.
public enum DiagnosticLevel: String, Sendable, Codable {
    case info = "INFO"
    case success = "SUCCESS"
    case warning = "WARNING"
    case error = "ERROR"
}

// MARK: - Diagnostic

/// A single diagnostic message with level and context.
public struct Diagnostic: Sendable, Codable {
    public let level: DiagnosticLevel
    public let message: String
    public let detail: String?
    public let suggestion: String?

    public init(
        level: DiagnosticLevel,
        message: String,
        detail: String? = nil,
        suggestion: String? = nil
    ) {
        self.level = level
        self.message = message
        self.detail = detail
        self.suggestion = suggestion
    }
}

// MARK: - Diagnostic Symbols

/// Unicode symbols for terminal output.
///
/// Degrades gracefully when color is disabled—symbols carry meaning
/// independent of color.
public enum DiagnosticSymbol {
    public static let success = "✓"
    public static let warning = "⚠"
    public static let error = "✕"
    public static let unknown = "?"
    public static let info = "ℹ"
    public static let arrow = "→"
    public static let bullet = "•"
    public static let progressFilled = "█"
    public static let progressEmpty = "░"
}

// MARK: - Color Support

/// Determines whether terminal color output is enabled.
///
/// Respects the `NO_COLOR` environment variable convention
/// (see https://no-color.org).
public struct ColorSupport: Sendable {
    public let isEnabled: Bool

    public init(forceDisable: Bool = false) {
        if forceDisable {
            self.isEnabled = false
        } else if ProcessInfo.processInfo.environment["NO_COLOR"] != nil {
            self.isEnabled = false
        } else {
            // Check if stdout is a TTY
            self.isEnabled = isatty(STDOUT_FILENO) != 0
        }
    }

    /// ANSI escape codes for terminal coloring.
    public enum ANSIColor: String, Sendable {
        case reset = "\u{001B}[0m"
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case blue = "\u{001B}[34m"
        case cyan = "\u{001B}[36m"
        case bold = "\u{001B}[1m"
        case dim = "\u{001B}[2m"
    }

    /// Wraps text in ANSI color codes if color is enabled.
    public func colored(_ text: String, _ color: ANSIColor) -> String {
        guard isEnabled else { return text }
        return "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
    }

    /// Bold text if color is enabled.
    public func bold(_ text: String) -> String {
        colored(text, .bold)
    }

    /// Dim text if color is enabled.
    public func dim(_ text: String) -> String {
        colored(text, .dim)
    }
}

// MARK: - Diagnostic Printer

/// Formats and prints diagnostic messages to stderr.
///
/// All diagnostic/logging output goes to stderr so that
/// stdout remains clean for JSON or machine-readable output.
public struct DiagnosticPrinter: Sendable {
    public let color: ColorSupport

    public init(color: ColorSupport = ColorSupport()) {
        self.color = color
    }

    /// Print a diagnostic to stderr.
    public func print(_ diagnostic: Diagnostic) {
        let symbol: String
        let colorCode: ColorSupport.ANSIColor

        switch diagnostic.level {
        case .info:
            symbol = DiagnosticSymbol.info
            colorCode = .cyan
        case .success:
            symbol = DiagnosticSymbol.success
            colorCode = .green
        case .warning:
            symbol = DiagnosticSymbol.warning
            colorCode = .yellow
        case .error:
            symbol = DiagnosticSymbol.error
            colorCode = .red
        }

        let prefix = color.colored(symbol, colorCode)
        var output = "\(prefix) \(diagnostic.message)"

        if let detail = diagnostic.detail {
            output += "\n  \(color.dim(detail))"
        }

        if let suggestion = diagnostic.suggestion {
            output += "\n  \(color.colored("Suggestion:", .cyan)) \(suggestion)"
        }

        FileHandle.standardError.write(Data((output + "\n").utf8))
    }

    /// Print a success message.
    public func success(_ message: String) {
        print(Diagnostic(level: .success, message: message))
    }

    /// Print a warning message.
    public func warning(_ message: String, detail: String? = nil) {
        print(Diagnostic(level: .warning, message: message, detail: detail))
    }

    /// Print an error message.
    public func error(_ message: String, detail: String? = nil, suggestion: String? = nil) {
        print(Diagnostic(level: .error, message: message, detail: detail, suggestion: suggestion))
    }

    /// Print an info message.
    public func info(_ message: String) {
        print(Diagnostic(level: .info, message: message))
    }

    /// Print a header line (bold).
    public func header(_ text: String) {
        let output = color.bold(text)
        FileHandle.standardError.write(Data((output + "\n").utf8))
    }

    /// Print a blank line to stderr.
    public func blank() {
        FileHandle.standardError.write(Data("\n".utf8))
    }

    /// Print raw text to stderr.
    public func raw(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    /// Render a progress bar.
    public func progressBar(percentage: Int, width: Int = 20) -> String {
        let clamped = max(0, min(100, percentage))
        let filled = (clamped * width) / 100
        let empty = width - filled
        return String(repeating: DiagnosticSymbol.progressFilled, count: filled)
            + String(repeating: DiagnosticSymbol.progressEmpty, count: empty)
            + " \(clamped)%"
    }
}
