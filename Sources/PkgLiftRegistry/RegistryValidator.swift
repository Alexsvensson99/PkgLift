import Foundation
import PkgLiftCore

/// Validates registry mappings to ensure they adhere to the schema and business rules.
public struct RegistryValidator: Sendable {
    public init() {}
    
    /// Validates a mapping.
    /// - Parameters:
    ///   - mapping: The `RegistryMapping` to validate.
    ///   - filePath: The path of the file being validated (for error reporting).
    /// - Returns: An array of `RegistryValidationError`s. Empty if valid.
    public func validate(_ mapping: RegistryMapping, filePath: String) -> [RegistryValidationError] {
        var errors: [RegistryValidationError] = []
        
        // 1. Schema version
        if mapping.schemaVersion != 1 {
            errors.append(RegistryValidationError(filePath: filePath, fieldPath: "schemaVersion", message: "Unsupported schema version: \(mapping.schemaVersion). Currently only version 1 is supported."))
        }
        
        // 2. Pod identifier
        if mapping.pod.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(RegistryValidationError(filePath: filePath, fieldPath: "pod.name", message: "Pod name cannot be empty."))
        }
        
        if let subspec = mapping.pod.subspec, subspec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(RegistryValidationError(filePath: filePath, fieldPath: "pod.subspec", message: "Subspec cannot be empty if provided."))
        }
        
        // 3. SwiftPM repository
        let repo = mapping.swiftpm.repository.trimmingCharacters(in: .whitespacesAndNewlines)
        if repo.isEmpty {
            errors.append(RegistryValidationError(filePath: filePath, fieldPath: "swiftpm.repository", message: "Repository URL cannot be empty."))
        } else if repo != mapping.swiftpm.repository {
            errors.append(RegistryValidationError(filePath: filePath, fieldPath: "swiftpm.repository", message: "Repository URL cannot contain surrounding whitespace."))
        } else if !isValidRepositoryURL(repo) {
            errors.append(RegistryValidationError(filePath: filePath, fieldPath: "swiftpm.repository", message: "Repository URL must be a complete HTTPS or git@host:path URL."))
        }
        
        // 4. SwiftPM products
        if mapping.swiftpm.products.isEmpty {
            errors.append(RegistryValidationError(filePath: filePath, fieldPath: "swiftpm.products", message: "Products list cannot be empty."))
        } else {
            for (index, product) in mapping.swiftpm.products.enumerated() {
                if product.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append(RegistryValidationError(filePath: filePath, fieldPath: "swiftpm.products[\(index)]", message: "Product name cannot be empty."))
                } else if product != product.trimmingCharacters(in: .whitespacesAndNewlines) {
                    errors.append(RegistryValidationError(filePath: filePath, fieldPath: "swiftpm.products[\(index)]", message: "Product name cannot contain surrounding whitespace."))
                }
            }
        }
        
        return errors
    }
    
    /// Validates a collection of mappings.
    /// - Parameter mappings: Dictionary of mappings keyed by their file paths.
    /// - Returns: An array of `RegistryValidationError`s.
    public func validateAll(_ mappings: [String: RegistryMapping]) -> [RegistryValidationError] {
        var allErrors: [RegistryValidationError] = []
        var seenIdentifiers: [String: String] = [:] // pod.fullName -> filePath
        
        for (filePath, mapping) in mappings {
            let errors = validate(mapping, filePath: filePath)
            allErrors.append(contentsOf: errors)
            
            let fullName = mapping.pod.fullName
            if let existingPath = seenIdentifiers[fullName] {
                allErrors.append(RegistryValidationError(filePath: filePath, fieldPath: "pod", message: "Duplicate mapping for pod '\(fullName)'. Also defined in \(existingPath)."))
            } else {
                seenIdentifiers[fullName] = filePath
            }
        }
        
        return allErrors
    }

    private func isValidRepositoryURL(_ value: String) -> Bool {
        if value.hasPrefix("https://") {
            guard let components = URLComponents(string: value),
                  components.scheme == "https",
                  components.host?.isEmpty == false,
                  !components.path.isEmpty,
                  components.path != "/" else { return false }
            return true
        }

        guard value.hasPrefix("git@"),
              let colon = value.firstIndex(of: ":"),
              colon > value.index(value.startIndex, offsetBy: 4),
              value.index(after: colon) < value.endIndex else { return false }
        return true
    }
}
