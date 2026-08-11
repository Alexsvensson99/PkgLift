import Foundation

/// Errors that can occur during registry operations.
public enum RegistryError: LocalizedError, Sendable {
    case invalidPath(String)
    case unreadableDirectory(String)
    case bundledRegistryNotFound([String])
    case validationFailed([RegistryValidationError])
    case parsingError(path: String, message: String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid registry path: \(path)"
        case .unreadableDirectory(let path):
            return "Could not read registry directory: \(path)"
        case .bundledRegistryNotFound(let searchedPaths):
            return "Could not find the bundled registry. Searched: \(searchedPaths.joined(separator: ", "))"
        case .validationFailed(let errors):
            return "Registry validation failed with \(errors.count) error(s)."
        case .parsingError(let path, let message):
            return "Failed to parse registry file at \(path): \(message)"
        }
    }
}

/// A specific validation error for a registry mapping.
public struct RegistryValidationError: Sendable, Equatable, CustomStringConvertible {
    public let filePath: String
    public let fieldPath: String
    public let message: String
    
    public init(filePath: String, fieldPath: String, message: String) {
        self.filePath = filePath
        self.fieldPath = fieldPath
        self.message = message
    }
    
    public var description: String {
        return "[\(filePath)] \(fieldPath): \(message)"
    }
}
