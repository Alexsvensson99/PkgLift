import Foundation

/// A consumer platform whose build environment can be resolved from Xcode.
public enum ConsumerPlatform: String, Sendable, Codable, CaseIterable, Comparable {
    case iOS
    case macOS
    case tvOS
    case watchOS
    case visionOS

    public static func < (lhs: ConsumerPlatform, rhs: ConsumerPlatform) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .iOS: 0
        case .macOS: 1
        case .tvOS: 2
        case .watchOS: 3
        case .visionOS: 4
        }
    }
}

/// Registry evidence for one supported consumer platform.
public struct SupportedConsumerPlatform: Sendable, Codable, Equatable, Hashable {
    public let platform: ConsumerPlatform
    public let minimumDeploymentTarget: String

    public init(platform: ConsumerPlatform, minimumDeploymentTarget: String) {
        self.platform = platform
        self.minimumDeploymentTarget = minimumDeploymentTarget
    }
}

/// A strict Apple deployment-target version with one to three numeric components.
///
/// Deployment targets are not package semantic versions: Xcode commonly emits
/// values such as `15` and `15.0`. Comparison pads omitted trailing components
/// with zeroes without accepting signs, suffixes, whitespace, or leading zeroes.
public struct DeploymentTargetVersion: Sendable, Hashable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(rawValue: String) {
        let components = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }

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
        while values.count < 3 {
            values.append(0)
        }

        self.major = values[0]
        self.minor = values[1]
        self.patch = values[2]
    }

    public static func < (lhs: DeploymentTargetVersion, rhs: DeploymentTargetVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
