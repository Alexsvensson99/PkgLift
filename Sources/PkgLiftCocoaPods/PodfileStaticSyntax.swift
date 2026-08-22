import Foundation
import PkgLiftCore

/// Small, conservative helpers for recognizing literal Podfile declarations.
///
/// This parser deliberately recognizes only syntax whose value can be proven
/// without evaluating Ruby. Unsupported or computed forms remain dynamic.
enum PodfileStaticSyntax {
    private static let rubyHorizontalWhitespace = CharacterSet(charactersIn: " \t")

    /// Statically recognized external Git source syntax on a single `pod`
    /// declaration. This is deliberately syntax evidence only: callers must
    /// not infer repository identity, resolve refs, or perform network I/O.
    enum ExternalGitSource: Sendable, Equatable {
        /// The declaration does not contain a literal Git source option.
        case none

        /// A complete, bounded literal Git source declaration.
        case supported(url: String, ref: GitRef?)

        /// A Git-looking declaration exists but cannot be represented without
        /// evaluating Ruby or accepting an unsupported option combination.
        case unsupported
    }

    static func containsUnsupportedLexicalCharacter(_ line: String) -> Bool {
        line.contains { character in
            if character == " " || character == "\t" {
                return false
            }
            if character.isWhitespace {
                return true
            }
            return character.unicodeScalars.contains { scalar in
                scalar.value < 0x20 || scalar.value == 0x7F
            }
        }
    }

    static func isDirectiveInvocation(_ directive: String, in line: String) -> Bool {
        let source = line.trimmingCharacters(in: rubyHorizontalWhitespace)
        guard source.hasPrefix(directive) else { return false }
        let boundary = source.index(source.startIndex, offsetBy: directive.count)
        guard boundary < source.endIndex else { return true }
        return isRubyHorizontalWhitespace(source[boundary]) || source[boundary] == "("
    }

    static func isTargetDeclaration(_ line: String) -> Bool {
        startsWithKeyword("target", line: line)
    }

    static func isPodDeclaration(_ line: String) -> Bool {
        startsWithKeyword("pod", line: line)
    }

    static func targetName(from line: String) -> String? {
        scopeName(from: line, keyword: "target", allowsParentheses: true)
    }

    static func abstractTargetName(from line: String) -> String? {
        scopeName(from: line, keyword: "abstract_target", allowsParentheses: false)
    }

    static func representablePodName(from line: String) -> String? {
        let source = line.trimmingCharacters(in: rubyHorizontalWhitespace)
        var index = source.startIndex
        guard let parenthesized = consumeInvocationKeyword("pod", in: source, index: &index) else {
            return nil
        }
        guard index < source.endIndex, source[index] == "'" || source[index] == "\"" else { return nil }
        guard let name = parseQuotedLiteral(in: source, index: &index), !name.isEmpty else { return nil }

        skipWhitespace(in: source, index: &index)
        if finishesInvocation(in: source, index: &index, parenthesized: parenthesized) {
            return name
        }

        guard index < source.endIndex, source[index] != ")" else { return nil }
        guard source[index] == "," else { return nil }
        index = source.index(after: index)
        skipWhitespace(in: source, index: &index)

        if consumeStaticModularHeadersOption(in: source, index: &index) {
            return finishesInvocation(in: source, index: &index, parenthesized: parenthesized)
                ? name
                : nil
        }

        guard index < source.endIndex,
              source[index] == "'" || source[index] == "\"",
              let version = parseQuotedLiteral(in: source, index: &index),
              !version.isEmpty else {
            return nil
        }
        skipWhitespace(in: source, index: &index)
        if finishesInvocation(in: source, index: &index, parenthesized: parenthesized) {
            return name
        }

        guard index < source.endIndex, source[index] != ")" else { return nil }
        guard source[index] == "," else { return nil }
        index = source.index(after: index)
        skipWhitespace(in: source, index: &index)
        guard consumeStaticModularHeadersOption(in: source, index: &index) else { return nil }
        return finishesInvocation(in: source, index: &index, parenthesized: parenthesized)
            ? name
            : nil
    }

    /// Recognizes one deliberately narrow, physical-line subset of CocoaPods'
    /// external Git syntax. Both hash-rocket and keyword options are accepted,
    /// but every option value must be a quoted Ruby literal. The grammar permits
    /// exactly one `git` option and at most one of `branch`, `tag`, or `commit`;
    /// all other options, expression tails, and malformed forms are rejected.
    static func externalGitSource(from line: String) -> ExternalGitSource {
        let source = line.trimmingCharacters(in: rubyHorizontalWhitespace)
        let hasGitMarker = containsGitOptionMarker(in: source)

        guard !containsUnsupportedLexicalCharacter(source) else {
            return hasGitMarker ? .unsupported : .none
        }

        var index = source.startIndex
        guard let parenthesized = consumeInvocationKeyword("pod", in: source, index: &index) else {
            return .none
        }
        guard index < source.endIndex, source[index] == "'" || source[index] == "\"",
              parseQuotedLiteral(in: source, index: &index) != nil else {
            return hasGitMarker ? .unsupported : .none
        }

        skipWhitespace(in: source, index: &index)
        if parenthesized, index < source.endIndex, source[index] == ")" {
            index = source.index(after: index)
            return finishesExternalGitInvocation(in: source, index: index)
                ? .none
                : (hasGitMarker ? .unsupported : .none)
        }
        guard index < source.endIndex, source[index] == "," else {
            return hasGitMarker ? .unsupported : .none
        }

        var gitURL: String?
        var ref: GitRef?
        var sawUnsupportedOption = false
        var sawPath = false
        var isFinished = false

        while !isFinished {
            guard index < source.endIndex, source[index] == "," else {
                return hasGitMarker ? .unsupported : .none
            }
            index = source.index(after: index)
            skipWhitespace(in: source, index: &index)

            guard let key = parseExternalGitOptionKey(in: source, index: &index) else {
                return hasGitMarker ? .unsupported : .none
            }
            skipWhitespace(in: source, index: &index)
            guard index < source.endIndex, source[index] == "'" || source[index] == "\"",
                  let value = parseQuotedLiteral(in: source, index: &index),
                  !value.isEmpty else {
                return hasGitMarker || key == "git" ? .unsupported : .none
            }

            switch key {
            case "git":
                if gitURL == nil {
                    gitURL = value
                } else {
                    sawUnsupportedOption = true
                }
            case "branch", "tag", "commit":
                if ref != nil {
                    sawUnsupportedOption = true
                } else {
                    ref = switch key {
                    case "branch": .branch(value)
                    case "tag": .tag(value)
                    case "commit": .commit(value)
                    default: nil
                    }
                }
            case "path":
                sawPath = true
            default:
                sawUnsupportedOption = true
            }

            skipWhitespace(in: source, index: &index)
            if parenthesized {
                if index < source.endIndex, source[index] == ")" {
                    index = source.index(after: index)
                    isFinished = true
                } else if index < source.endIndex, source[index] == "," {
                    continue
                } else {
                    return hasGitMarker || gitURL != nil ? .unsupported : .none
                }
            } else if index == source.endIndex || source[index] == "#" {
                isFinished = true
            } else if source[index] == "," {
                continue
            } else {
                return hasGitMarker || gitURL != nil ? .unsupported : .none
            }
        }

        guard finishesExternalGitInvocation(in: source, index: index) else {
            return hasGitMarker || gitURL != nil ? .unsupported : .none
        }
        guard let gitURL, !sawUnsupportedOption, !sawPath else {
            return hasGitMarker ? .unsupported : .none
        }
        return .supported(url: gitURL, ref: ref)
    }

    private static func scopeName(
        from line: String,
        keyword: String,
        allowsParentheses: Bool
    ) -> String? {
        let source = line.trimmingCharacters(in: rubyHorizontalWhitespace)
        var index = source.startIndex
        guard let parenthesized = consumeInvocationKeyword(keyword, in: source, index: &index),
              allowsParentheses || !parenthesized else {
            return nil
        }
        let name: String?
        if parenthesized {
            guard index < source.endIndex, source[index] == "'" || source[index] == "\"" else {
                return nil
            }
            name = parseQuotedLiteral(in: source, index: &index)
        } else {
            name = parseLiteralName(in: source, index: &index)
        }
        guard let name, !name.isEmpty else { return nil }

        skipWhitespace(in: source, index: &index)
        if parenthesized {
            guard index < source.endIndex, source[index] == ")" else { return nil }
            index = source.index(after: index)
            guard index < source.endIndex, isRubyHorizontalWhitespace(source[index]) else {
                return nil
            }
            skipWhitespace(in: source, index: &index)
        }
        guard consumeWord("do", in: source, index: &index) else { return nil }
        skipWhitespace(in: source, index: &index)

        guard index == source.endIndex || source[index] == "#" else { return nil }
        return name
    }

    static func podName(from line: String) -> String? {
        let source = line.trimmingCharacters(in: rubyHorizontalWhitespace)
        var index = source.startIndex
        guard consumeInvocationKeyword("pod", in: source, index: &index) != nil else { return nil }
        guard index < source.endIndex, source[index] == "'" || source[index] == "\"" else { return nil }
        guard let name = parseQuotedLiteral(in: source, index: &index), !name.isEmpty else { return nil }
        return name
    }

    static func closesBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: rubyHorizontalWhitespace)
        return trimmed.range(
            of: #"^end(?:\s*(?:#.*)?)$"#,
            options: .regularExpression
        ) != nil
    }

    static func opensNonTargetBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: rubyHorizontalWhitespace)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return false }
        guard !isTargetDeclaration(trimmed) else { return false }

        let blockPrefixes = [
            "def ", "if ", "unless ", "case ", "for ", "while ", "until ",
            "class ", "module ", "begin", "abstract_target ", "post_install ",
            "pre_install ",
        ]
        if blockPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }

        return trimmed.range(
            of: #"\bdo(?:\s*\|[^|]*\|)?\s*(?:#.*)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func startsWithKeyword(_ keyword: String, line: String) -> Bool {
        let source = line.trimmingCharacters(in: rubyHorizontalWhitespace)
        guard source.hasPrefix(keyword) else { return false }
        let boundary = source.index(source.startIndex, offsetBy: keyword.count)
        return boundary < source.endIndex
            && (isRubyHorizontalWhitespace(source[boundary]) || source[boundary] == "(")
    }

    private static func containsGitOptionMarker(in source: String) -> Bool {
        var executable = ""
        var index = source.startIndex

        while index < source.endIndex {
            let character = source[index]
            if character == "#" {
                break
            }
            if character == "'" || character == "\"" {
                let quote = character
                executable.append(" ")
                index = source.index(after: index)
                while index < source.endIndex {
                    let quotedCharacter = source[index]
                    if quotedCharacter == "\\" {
                        executable.append(" ")
                        index = source.index(after: index)
                        if index < source.endIndex {
                            executable.append(" ")
                            index = source.index(after: index)
                        }
                        continue
                    }
                    executable.append(" ")
                    index = source.index(after: index)
                    if quotedCharacter == quote {
                        break
                    }
                }
                continue
            }
            executable.append(character)
            index = source.index(after: index)
        }

        return executable.range(
            of: #"(?:^|[,\s])(?::git\b|git\s*:)"#,
            options: .regularExpression
        ) != nil
    }

    private static func parseExternalGitOptionKey(
        in source: String,
        index: inout String.Index
    ) -> String? {
        guard index < source.endIndex else { return nil }

        if source[index] == ":" {
            index = source.index(after: index)
            guard let key = consumeIdentifier(in: source, index: &index) else { return nil }
            skipWhitespace(in: source, index: &index)
            guard index < source.endIndex, source[index] == "=" else { return nil }
            index = source.index(after: index)
            guard index < source.endIndex, source[index] == ">" else { return nil }
            index = source.index(after: index)
            return key
        }

        guard let key = consumeIdentifier(in: source, index: &index) else { return nil }
        guard index < source.endIndex, source[index] == ":" else { return nil }
        index = source.index(after: index)
        return key
    }

    private static func consumeIdentifier(in source: String, index: inout String.Index) -> String? {
        guard index < source.endIndex, isIdentifierStart(source[index]) else { return nil }
        let start = index
        index = source.index(after: index)
        while index < source.endIndex, isIdentifierContinuation(source[index]) {
            index = source.index(after: index)
        }
        return String(source[start..<index])
    }

    private static func finishesExternalGitInvocation(in source: String, index: String.Index) -> Bool {
        var trailing = index
        skipWhitespace(in: source, index: &trailing)
        return trailing == source.endIndex || source[trailing] == "#"
    }

    private static func consumeStaticModularHeadersOption(
        in source: String,
        index: inout String.Index
    ) -> Bool {
        let remainder = source[index...]
        guard let match = remainder.range(
            of: #"^(?:modular_headers\s*:\s*true|:modular_headers\s*=>\s*true)"#,
            options: .regularExpression
        ) else {
            return false
        }
        index = match.upperBound
        return true
    }

    /// Consumes a Ruby method name and returns whether its arguments start with
    /// an immediate opening parenthesis. Whitespace followed by a parenthesis
    /// is deliberately not accepted as a new syntax form.
    private static func consumeInvocationKeyword(
        _ keyword: String,
        in source: String,
        index: inout String.Index
    ) -> Bool? {
        guard source[index...].hasPrefix(keyword) else { return nil }
        let boundary = source.index(index, offsetBy: keyword.count)
        guard boundary < source.endIndex else { return nil }
        if source[boundary] == "(" {
            index = source.index(after: boundary)
            return true
        }
        guard isRubyHorizontalWhitespace(source[boundary]) else { return nil }
        index = boundary
        skipWhitespace(in: source, index: &index)
        return false
    }

    private static func finishesInvocation(
        in source: String,
        index: inout String.Index,
        parenthesized: Bool
    ) -> Bool {
        skipWhitespace(in: source, index: &index)
        if parenthesized {
            guard index < source.endIndex, source[index] == ")" else { return false }
            let closingParenthesis = index
            var trailingIndex = source.index(after: index)
            skipWhitespace(in: source, index: &trailingIndex)
            guard trailingIndex == source.endIndex || source[trailingIndex] == "#" else {
                index = closingParenthesis
                return false
            }
            index = trailingIndex
        }
        return index == source.endIndex || source[index] == "#"
    }

    private static func consumeWord(_ word: String, in source: String, index: inout String.Index) -> Bool {
        guard source[index...].hasPrefix(word) else { return false }
        let boundary = source.index(index, offsetBy: word.count)
        if boundary < source.endIndex {
            let character = source[boundary]
            guard isRubyHorizontalWhitespace(character) || character == "#" else {
                return false
            }
        }
        index = boundary
        return true
    }

    private static func parseLiteralName(in source: String, index: inout String.Index) -> String? {
        guard index < source.endIndex else { return nil }

        if source[index] == "'" || source[index] == "\"" {
            return parseQuotedLiteral(in: source, index: &index)
        }

        guard source[index] == ":" else { return nil }
        index = source.index(after: index)
        guard index < source.endIndex else { return nil }

        if source[index] == "'" || source[index] == "\"" {
            return parseQuotedLiteral(in: source, index: &index)
        }

        guard isIdentifierStart(source[index]) else { return nil }
        var value = String(source[index])
        index = source.index(after: index)

        while index < source.endIndex, isIdentifierContinuation(source[index]) {
            value.append(source[index])
            index = source.index(after: index)
        }
        return value
    }

    private static func parseQuotedLiteral(in source: String, index: inout String.Index) -> String? {
        guard index < source.endIndex else { return nil }
        let quote = source[index]
        guard quote == "'" || quote == "\"" else { return nil }
        index = source.index(after: index)

        var value = ""
        while index < source.endIndex {
            let character = source[index]

            if character == "\\" {
                let escapedIndex = source.index(after: index)
                guard escapedIndex < source.endIndex else { return nil }
                let escaped = source[escapedIndex]
                guard escaped == quote || escaped == "\\" else { return nil }
                value.append(escaped)
                index = source.index(after: escapedIndex)
                continue
            }

            if character == quote {
                index = source.index(after: index)
                return value
            }

            if quote == "\"", character == "#" {
                let next = source.index(after: index)
                if next < source.endIndex, source[next] == "{" || source[next] == "@" || source[next] == "$" {
                    return nil
                }
            }

            if character.unicodeScalars.contains(where: { scalar in
                scalar.value < 0x20 || scalar.value == 0x7F
            }) {
                return nil
            }

            value.append(character)
            index = source.index(after: index)
        }

        return nil
    }

    private static func skipWhitespace(in source: String, index: inout String.Index) {
        while index < source.endIndex, isRubyHorizontalWhitespace(source[index]) {
            index = source.index(after: index)
        }
    }

    private static func isRubyHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }
}
