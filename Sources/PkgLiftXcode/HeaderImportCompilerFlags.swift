// PkgLiftXcode/HeaderImportCompilerFlags.swift
// Bounded allowlist for compiler flags reviewed with header imports.

import Foundation

enum HeaderImportCompilerFlags {
    private static let maximumBytes = 64 * 1_024
    private static let maximumTokens = 512

    static func accepts(value: String, setting: String) -> Bool {
        guard let tokens = tokenize(value) else { return false }
        switch setting {
        case "OTHER_CFLAGS", "OTHER_CPLUSPLUSFLAGS":
            return acceptsCFlags(tokens)
        case "OTHER_SWIFT_FLAGS":
            return acceptsSwiftFlags(tokens)
        default:
            return false
        }
    }

    private static func acceptsCFlags(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "$(inherited)" {
                index += 1
            } else if token == "-D" {
                guard index + 1 < tokens.count, isCMacro(tokens[index + 1]) else { return false }
                index += 2
            } else if token == "-U" {
                guard index + 1 < tokens.count, isIdentifier(tokens[index + 1]) else { return false }
                index += 2
            } else if token.hasPrefix("-D"), isCMacro(String(token.dropFirst(2))) {
                index += 1
            } else if token.hasPrefix("-U"), isIdentifier(String(token.dropFirst(2))) {
                index += 1
            } else if isModuleMapFlag(token) {
                index += 1
            } else {
                return false
            }
        }
        return true
    }

    private static func acceptsSwiftFlags(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "$(inherited)" {
                index += 1
            } else if token == "-D" {
                guard index + 1 < tokens.count, isIdentifier(tokens[index + 1]) else { return false }
                index += 2
            } else if token.hasPrefix("-D"), isIdentifier(String(token.dropFirst(2))) {
                index += 1
            } else if token == "-Xcc" {
                guard index + 1 < tokens.count, isModuleMapFlag(tokens[index + 1]) else { return false }
                index += 2
            } else {
                return false
            }
        }
        return true
    }

    private static func tokenize(_ value: String) -> [String]? {
        guard value.utf8.count <= maximumBytes else { return nil }
        var tokens: [String] = []
        var token = ""
        var quoted = false
        var hasToken = false
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 32, 9:
                if quoted {
                    token.unicodeScalars.append(scalar)
                } else if hasToken {
                    tokens.append(token)
                    guard tokens.count <= maximumTokens else { return nil }
                    token = ""
                    hasToken = false
                }
            case 34:
                quoted.toggle()
                hasToken = true
            case 92:
                return nil
            case 0...31, 127:
                return nil
            default:
                token.unicodeScalars.append(scalar)
                hasToken = true
            }
        }
        guard !quoted else { return nil }
        if hasToken {
            tokens.append(token)
        }
        return tokens.count <= maximumTokens ? tokens : nil
    }

    private static func isCMacro(_ value: String) -> Bool {
        let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard let name = parts.first, isIdentifier(String(name)) else { return false }
        return parts.count == 1 || (parts.count == 2 && isDecimal(String(parts[1])))
    }

    private static func isIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              (first.value >= 65 && first.value <= 90) || (first.value >= 97 && first.value <= 122) || first.value == 95 else {
            return false
        }
        return value.unicodeScalars.dropFirst().allSatisfy {
            ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) ||
                ($0.value >= 48 && $0.value <= 57) || $0.value == 95
        }
    }

    private static func isDecimal(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }

    private static func isModuleMapFlag(_ token: String) -> Bool {
        let prefix = "-fmodule-map-file="
        guard token.hasPrefix(prefix) else { return false }
        let path = String(token.dropFirst(prefix.count))
        let roots = [
            "${PODS_CONFIGURATION_BUILD_DIR}/", "$(PODS_CONFIGURATION_BUILD_DIR)/",
            "${PODS_ROOT}/Headers/Public/", "$(PODS_ROOT)/Headers/Public/"
        ]
        guard let root = roots.first(where: { path.hasPrefix($0) }) else { return false }
        let relative = String(path.dropFirst(root.count))
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard relative.hasSuffix(".modulemap"), !components.isEmpty else { return false }
        return components.allSatisfy { component in
            guard !component.isEmpty, component != ".", component != ".." else { return false }
            return component.unicodeScalars.allSatisfy {
                ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) ||
                    ($0.value >= 48 && $0.value <= 57) || $0.value == 46 || $0.value == 95 || $0.value == 45 || $0.value == 43
            }
        }
    }
}
