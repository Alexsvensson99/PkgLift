// PkgLiftCocoaPods/PodspecLinkageSemanticModel.swift
// Typed, analysis-only linkage, module, header, and vendored input declarations.

import Foundation

/// One exact, non-empty string declaration and its RFC 6901 source path.
///
/// The literal is opaque. PkgLift does not expand globs, standardize paths, inspect files,
/// infer artifact kinds, or otherwise project the declaration onto SwiftPM.
public struct PodspecLiteralDeclaration: Sendable, Equatable, Codable {
    public let literal: String
    public let path: String

    public init(literal: String, path: String) {
        self.literal = literal
        self.path = path
    }
}

/// One explicit JSON boolean declaration and its RFC 6901 source path.
public struct PodspecBooleanDeclaration: Sendable, Equatable, Codable {
    public let value: Bool
    public let path: String

    public init(value: Bool, path: String) {
        self.value = value
        self.path = path
    }
}

/// One explicit CocoaPods module-map declaration.
///
/// `generated` and `disabled` correspond to literal JSON `true` and `false`. A custom path
/// remains opaque and is never opened or validated as a module map.
public struct PodspecModuleMapDeclaration: Sendable, Equatable, Codable {
    public enum Value: Sendable, Equatable, Codable {
        case generated
        case disabled
        case customPath(String)
    }

    public let value: Value
    public let path: String

    public init(value: Value, path: String) {
        self.value = value
        self.path = path
    }
}

/// Raw linkage, module, header-layout, and vendored-input declarations in one scope.
///
/// Parent, child, global, and platform values remain separate. This type never computes
/// CocoaPods' effective consumer view or claims source, binary, module, or SwiftPM equivalence.
public struct PodspecLinkageDeclarations: Sendable, Equatable, Codable {
    public let frameworks: [PodspecLiteralDeclaration]
    public let weakFrameworks: [PodspecLiteralDeclaration]
    public let libraries: [PodspecLiteralDeclaration]
    public let vendoredFrameworks: [PodspecLiteralDeclaration]
    public let vendoredLibraries: [PodspecLiteralDeclaration]
    public let moduleName: PodspecLiteralDeclaration?
    public let moduleMap: PodspecModuleMapDeclaration?
    public let headerDirectory: PodspecLiteralDeclaration?
    public let headerMappingsDirectory: PodspecLiteralDeclaration?
    public let projectHeaders: [PodspecLiteralDeclaration]
    public let staticFramework: PodspecBooleanDeclaration?

    public init(
        frameworks: [PodspecLiteralDeclaration] = [],
        weakFrameworks: [PodspecLiteralDeclaration] = [],
        libraries: [PodspecLiteralDeclaration] = [],
        vendoredFrameworks: [PodspecLiteralDeclaration] = [],
        vendoredLibraries: [PodspecLiteralDeclaration] = [],
        moduleName: PodspecLiteralDeclaration? = nil,
        moduleMap: PodspecModuleMapDeclaration? = nil,
        headerDirectory: PodspecLiteralDeclaration? = nil,
        headerMappingsDirectory: PodspecLiteralDeclaration? = nil,
        projectHeaders: [PodspecLiteralDeclaration] = [],
        staticFramework: PodspecBooleanDeclaration? = nil
    ) {
        self.frameworks = frameworks
        self.weakFrameworks = weakFrameworks
        self.libraries = libraries
        self.vendoredFrameworks = vendoredFrameworks
        self.vendoredLibraries = vendoredLibraries
        self.moduleName = moduleName
        self.moduleMap = moduleMap
        self.headerDirectory = headerDirectory
        self.headerMappingsDirectory = headerMappingsDirectory
        self.projectHeaders = projectHeaders
        self.staticFramework = staticFramework
    }

    public static let empty = PodspecLinkageDeclarations()
}
