import Foundation

/// Small, conservative helpers for recognizing literal Podfile declarations.
///
/// This parser deliberately recognizes only syntax whose value can be proven
/// without evaluating Ruby. Unsupported or computed forms remain dynamic.
enum PodfileStaticSyntax {
    static func isTargetDeclaration(_ line: String) -> Bool {
        startsWithKeyword("target", line: line)
    }

    static func isPodDeclaration(_ line: String) -> Bool {
        startsWithKeyword("pod", line: line)
    }

    static func targetName(from line: String) -> String? {
        scopeName(from: line, keyword: "target")
    }

    static func abstractTargetName(from line: String) -> String? {
        scopeName(from: line, keyword: "abstract_target")
    }

    static func representablePodName(from line: String) -> String? {
        let source = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var index = source.startIndex
        guard consumeKeyword("pod", in: source, index: &index) else { return nil }
        guard index < source.endIndex, source[index] == "'" || source[index] == "\"" else { return nil }
        guard let name = parseQuotedLiteral(in: source, index: &index), !name.isEmpty else { return nil }

        skipWhitespace(in: source, index: &index)
        if index == source.endIndex || source[index] == "#" {
            return name
        }

        guard source[index] == "," else { return nil }
        index = source.index(after: index)
        skipWhitespace(in: source, index: &index)
        guard index < source.endIndex, source[index] == "'" || source[index] == "\"" else { return nil }
        guard let version = parseQuotedLiteral(in: source, index: &index), !version.isEmpty else { return nil }
        skipWhitespace(in: source, index: &index)
        guard index == source.endIndex || source[index] == "#" else { return nil }
        return name
    }

    private static func scopeName(from line: String, keyword: String) -> String? {
        let source = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var index = source.startIndex
        guard consumeKeyword(keyword, in: source, index: &index) else { return nil }
        guard let name = parseLiteralName(in: source, index: &index), !name.isEmpty else { return nil }

        skipWhitespace(in: source, index: &index)
        guard consumeWord("do", in: source, index: &index) else { return nil }
        skipWhitespace(in: source, index: &index)

        guard index == source.endIndex || source[index] == "#" else { return nil }
        return name
    }

    static func podName(from line: String) -> String? {
        let source = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var index = source.startIndex
        guard consumeKeyword("pod", in: source, index: &index) else { return nil }
        guard index < source.endIndex, source[index] == "'" || source[index] == "\"" else { return nil }
        guard let name = parseQuotedLiteral(in: source, index: &index), !name.isEmpty else { return nil }
        return name
    }

    static func closesBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(
            of: #"^end(?:\s*(?:#.*)?)$"#,
            options: .regularExpression
        ) != nil
    }

    static func opensNonTargetBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let source = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.hasPrefix(keyword) else { return false }
        let boundary = source.index(source.startIndex, offsetBy: keyword.count)
        return boundary < source.endIndex && source[boundary].isWhitespace
    }

    private static func consumeKeyword(_ keyword: String, in source: String, index: inout String.Index) -> Bool {
        guard source[index...].hasPrefix(keyword) else { return false }
        let boundary = source.index(index, offsetBy: keyword.count)
        guard boundary < source.endIndex, source[boundary].isWhitespace else { return false }
        index = boundary
        skipWhitespace(in: source, index: &index)
        return true
    }

    private static func consumeWord(_ word: String, in source: String, index: inout String.Index) -> Bool {
        guard source[index...].hasPrefix(word) else { return false }
        let boundary = source.index(index, offsetBy: word.count)
        if boundary < source.endIndex {
            let character = source[boundary]
            guard character.isWhitespace || character == "#" else { return false }
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

            value.append(character)
            index = source.index(after: index)
        }

        return nil
    }

    private static func skipWhitespace(in source: String, index: inout String.Index) {
        while index < source.endIndex, source[index].isWhitespace {
            index = source.index(after: index)
        }
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }
}
