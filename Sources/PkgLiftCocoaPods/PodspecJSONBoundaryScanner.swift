// PkgLiftCocoaPods/PodspecJSONBoundaryScanner.swift
// Bounded JSON grammar scan before Foundation materializes untrusted input.

import Foundation

/// Validates JSON structure, resource limits, and unique object keys before
/// `JSONSerialization` creates an object graph. String tokens are decoded one
/// at a time with Foundation so Unicode escape handling remains standards-based.
struct PodspecJSONBoundaryScanner {
    private let bytes: [UInt8]
    private let limits: PodspecInspectionLimits
    private var index = 0
    private var totalValues = 0

    init(data: Data, limits: PodspecInspectionLimits) {
        self.bytes = Array(data)
        self.limits = limits
    }

    mutating func validate() throws {
        skipWhitespace()
        try parseValue(path: "", depth: 0)
        skipWhitespace()
        guard index == bytes.count else {
            throw PodspecInspectionError.malformedJSON
        }
    }

    private mutating func parseValue(path: String, depth: Int) throws {
        guard depth <= limits.maximumNestingDepth else {
            throw PodspecInspectionError.limitExceeded(
                path: path,
                actual: depth,
                maximum: limits.maximumNestingDepth
            )
        }

        totalValues += 1
        guard totalValues <= limits.maximumTotalValues else {
            throw PodspecInspectionError.limitExceeded(
                path: path,
                actual: totalValues,
                maximum: limits.maximumTotalValues
            )
        }

        guard let byte = currentByte else {
            throw PodspecInspectionError.malformedJSON
        }
        switch byte {
        case Self.leftBrace:
            try parseObject(path: path, depth: depth)
        case Self.leftBracket:
            try parseArray(path: path, depth: depth)
        case Self.quotationMark:
            let string = try parseStringToken()
            try validateStringSize(string, path: path)
        case Self.lowercaseT:
            try consumeLiteral(Self.trueLiteral)
        case Self.lowercaseF:
            try consumeLiteral(Self.falseLiteral)
        case Self.lowercaseN:
            try consumeLiteral(Self.nullLiteral)
        case Self.minus, Self.zero...Self.nine:
            try parseNumber()
        default:
            throw PodspecInspectionError.malformedJSON
        }
    }

    private mutating func parseObject(path: String, depth: Int) throws {
        try consumeRequired(Self.leftBrace)
        skipWhitespace()
        if consume(Self.rightBrace) { return }

        var keys: Set<String> = []
        var memberCount = 0
        while true {
            guard currentByte == Self.quotationMark else {
                throw PodspecInspectionError.malformedJSON
            }
            let key = try parseStringToken()
            let childPath = PodspecJSONPointer.appending(key, to: path)
            try validateStringSize(key, path: childPath)
            guard keys.insert(key).inserted else {
                throw PodspecInspectionError.duplicateObjectKey(path: childPath)
            }

            memberCount += 1
            try validateContainerCount(memberCount, path: path)
            skipWhitespace()
            try consumeRequired(Self.colon)
            skipWhitespace()
            try parseValue(path: childPath, depth: depth + 1)
            skipWhitespace()

            if consume(Self.rightBrace) { return }
            try consumeRequired(Self.comma)
            skipWhitespace()
        }
    }

    private mutating func parseArray(path: String, depth: Int) throws {
        try consumeRequired(Self.leftBracket)
        skipWhitespace()
        if consume(Self.rightBracket) { return }

        var elementCount = 0
        while true {
            elementCount += 1
            try validateContainerCount(elementCount, path: path)
            try parseValue(
                path: PodspecJSONPointer.appending(String(elementCount - 1), to: path),
                depth: depth + 1
            )
            skipWhitespace()

            if consume(Self.rightBracket) { return }
            try consumeRequired(Self.comma)
            skipWhitespace()
        }
    }

    private mutating func parseStringToken() throws -> String {
        let start = index
        try consumeRequired(Self.quotationMark)

        while let byte = currentByte {
            if byte == Self.quotationMark {
                index += 1
                let token = Data(bytes[start..<index])
                do {
                    let decoded = try JSONSerialization.jsonObject(
                        with: token,
                        options: [.fragmentsAllowed]
                    )
                    guard let string = decoded as? String else {
                        throw PodspecInspectionError.malformedJSON
                    }
                    return string
                } catch let error as PodspecInspectionError {
                    throw error
                } catch {
                    throw PodspecInspectionError.malformedJSON
                }
            }

            guard byte >= Self.space else {
                throw PodspecInspectionError.malformedJSON
            }
            if byte == Self.backslash {
                index += 1
                guard let escape = currentByte else {
                    throw PodspecInspectionError.malformedJSON
                }
                switch escape {
                case Self.quotationMark,
                     Self.backslash,
                     Self.slash,
                     Self.lowercaseB,
                     Self.lowercaseF,
                     Self.lowercaseN,
                     Self.lowercaseR,
                     Self.lowercaseT:
                    index += 1
                case Self.lowercaseU:
                    index += 1
                    for _ in 0..<4 {
                        guard let hex = currentByte, Self.isHexDigit(hex) else {
                            throw PodspecInspectionError.malformedJSON
                        }
                        index += 1
                    }
                default:
                    throw PodspecInspectionError.malformedJSON
                }
            } else {
                index += 1
            }
        }

        throw PodspecInspectionError.malformedJSON
    }

    private mutating func parseNumber() throws {
        _ = consume(Self.minus)
        guard let firstDigit = currentByte else {
            throw PodspecInspectionError.malformedJSON
        }
        if firstDigit == Self.zero {
            index += 1
        } else {
            guard Self.one...Self.nine ~= firstDigit else {
                throw PodspecInspectionError.malformedJSON
            }
            consumeDigits()
        }

        if consume(Self.period) {
            guard let digit = currentByte, Self.zero...Self.nine ~= digit else {
                throw PodspecInspectionError.malformedJSON
            }
            consumeDigits()
        }

        if consume(Self.lowercaseE) || consume(Self.uppercaseE) {
            if !consume(Self.plus) {
                _ = consume(Self.minus)
            }
            guard let digit = currentByte, Self.zero...Self.nine ~= digit else {
                throw PodspecInspectionError.malformedJSON
            }
            consumeDigits()
        }
    }

    private mutating func consumeDigits() {
        while let byte = currentByte, Self.zero...Self.nine ~= byte {
            index += 1
        }
    }

    private mutating func consumeLiteral(_ literal: [UInt8]) throws {
        guard index + literal.count <= bytes.count,
              Array(bytes[index..<(index + literal.count)]) == literal else {
            throw PodspecInspectionError.malformedJSON
        }
        index += literal.count
    }

    private mutating func consumeRequired(_ byte: UInt8) throws {
        guard consume(byte) else {
            throw PodspecInspectionError.malformedJSON
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard currentByte == byte else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while let byte = currentByte,
              byte == Self.space
                || byte == Self.tab
                || byte == Self.lineFeed
                || byte == Self.carriageReturn {
            index += 1
        }
    }

    private func validateContainerCount(_ count: Int, path: String) throws {
        guard count <= limits.maximumContainerElements else {
            throw PodspecInspectionError.limitExceeded(
                path: path,
                actual: count,
                maximum: limits.maximumContainerElements
            )
        }
    }

    private func validateStringSize(_ value: String, path: String) throws {
        let byteCount = value.lengthOfBytes(using: .utf8)
        guard byteCount <= limits.maximumStringUTF8Bytes else {
            throw PodspecInspectionError.limitExceeded(
                path: path,
                actual: byteCount,
                maximum: limits.maximumStringUTF8Bytes
            )
        }
    }

    private var currentByte: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        zero...nine ~= byte
            || uppercaseA...uppercaseF ~= byte
            || lowercaseA...lowercaseF ~= byte
    }

    private static let quotationMark: UInt8 = 0x22
    private static let plus: UInt8 = 0x2B
    private static let comma: UInt8 = 0x2C
    private static let minus: UInt8 = 0x2D
    private static let period: UInt8 = 0x2E
    private static let slash: UInt8 = 0x2F
    private static let zero: UInt8 = 0x30
    private static let one: UInt8 = 0x31
    private static let nine: UInt8 = 0x39
    private static let colon: UInt8 = 0x3A
    private static let uppercaseA: UInt8 = 0x41
    private static let uppercaseE: UInt8 = 0x45
    private static let uppercaseF: UInt8 = 0x46
    private static let leftBracket: UInt8 = 0x5B
    private static let backslash: UInt8 = 0x5C
    private static let rightBracket: UInt8 = 0x5D
    private static let lowercaseA: UInt8 = 0x61
    private static let lowercaseB: UInt8 = 0x62
    private static let lowercaseE: UInt8 = 0x65
    private static let lowercaseF: UInt8 = 0x66
    private static let lowercaseN: UInt8 = 0x6E
    private static let lowercaseR: UInt8 = 0x72
    private static let lowercaseT: UInt8 = 0x74
    private static let lowercaseU: UInt8 = 0x75
    private static let leftBrace: UInt8 = 0x7B
    private static let rightBrace: UInt8 = 0x7D
    private static let space: UInt8 = 0x20
    private static let tab: UInt8 = 0x09
    private static let lineFeed: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    private static let trueLiteral = Array("true".utf8)
    private static let falseLiteral = Array("false".utf8)
    private static let nullLiteral = Array("null".utf8)
}
