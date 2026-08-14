import Foundation

/// A stable semantic version with exactly three numeric components.
///
/// PkgLift uses this strict representation when comparing a resolved
/// CocoaPods version with registry evidence. Pre-release, build metadata,
/// abbreviated, and otherwise ambiguous versions are deliberately rejected.
public struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(rawValue: String) {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }

        var values: [Int] = []
        values.reserveCapacity(3)

        for component in components {
            guard !component.isEmpty,
                  component.allSatisfy({ $0.isASCII && $0.isNumber }),
                  component.count == 1 || component.first != "0",
                  let value = Int(component) else {
                return nil
            }
            values.append(value)
        }

        self.major = values[0]
        self.minor = values[1]
        self.patch = values[2]
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}
