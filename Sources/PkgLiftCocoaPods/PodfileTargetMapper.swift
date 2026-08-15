// PkgLiftCocoaPods/PodfileTargetMapper.swift
// Maps dependencies to targets based on Podfile blocks.

import Foundation
import PkgLiftCore

/// Maps CocoaPods dependencies to targets based only on literal Podfile structure.
public struct PodfileTargetMapper: Sendable {
    public init() {}

    /// Backward-compatible lockfile mapping API.
    ///
    /// Target evidence is matched by the exact pod or subspec name. A base-pod
    /// declaration is never used as target evidence for a subspec.
    public func map(
        podfileContent: String,
        lockfileDependencies: [CocoaPodDependency]
    ) -> [CocoaPodDependency] {
        let parsed = PodfileParser().parse(content: podfileContent)
        let declarations = mapDeclarations(
            parsed.directDependencies,
            lockfileDependencies: lockfileDependencies
        )
        return mapLockfileDependencies(
            lockfileDependencies,
            declarations: declarations
        )
    }

    /// Adds exact lockfile version/source evidence to every literal declaration
    /// without copying target evidence between declarations that share a name.
    public func mapDeclarations(
        _ declarations: [CocoaPodDependency],
        lockfileDependencies: [CocoaPodDependency]
    ) -> [CocoaPodDependency] {
        declarations.map { declaration in
            let resolved = lockfileDependencies.first { $0.name == declaration.name }
            let source = declaration.source == .registry
                ? resolved?.source ?? .registry
                : declaration.source
            let origins = declaration.declarations?.map { origin in
                PodfileDeclaration(
                    line: origin.line,
                    scope: origin.scope,
                    scopeName: origin.scopeName,
                    targetName: origin.targetName,
                    source: source
                )
            }

            return CocoaPodDependency(
                name: declaration.name,
                version: resolved?.version,
                source: source,
                isDirect: true,
                targets: declaration.targets,
                declarations: origins,
                targetAttribution: declaration.effectiveTargetAttribution
            )
        }
    }

    /// Applies exact declaration evidence to each unique lockfile dependency.
    public func mapLockfileDependencies(
        _ lockfileDependencies: [CocoaPodDependency],
        declarations: [CocoaPodDependency]
    ) -> [CocoaPodDependency] {
        let declarationsByName = Dictionary(grouping: declarations, by: \.name)

        var seenNames: Set<String> = []
        return lockfileDependencies.compactMap { dependency in
            guard seenNames.insert(dependency.name).inserted else {
                return nil
            }
            let matchingDeclarations = declarationsByName[dependency.name] ?? []
            guard !matchingDeclarations.isEmpty else {
                return CocoaPodDependency(
                    name: dependency.name,
                    version: dependency.version,
                    source: dependency.source,
                    isDirect: dependency.isDirect,
                    targets: [],
                    declarations: nil,
                    targetAttribution: TargetAttribution.legacyFallback(
                        from: [],
                        isDirect: dependency.isDirect
                    )
                )
            }

            guard let aggregate = aggregateDirectDependencies(matchingDeclarations).first else {
                return CocoaPodDependency(
                    name: dependency.name,
                    version: dependency.version,
                    source: dependency.source,
                    isDirect: dependency.isDirect,
                    targets: [],
                    declarations: nil,
                    targetAttribution: TargetAttribution.legacyFallback(
                        from: [],
                        isDirect: dependency.isDirect
                    )
                )
            }
            let source = dependency.source == .registry
                ? aggregate.source
                : dependency.source
            return CocoaPodDependency(
                name: dependency.name,
                version: dependency.version,
                source: source,
                isDirect: dependency.isDirect,
                targets: aggregate.targets,
                declarations: aggregate.declarations,
                targetAttribution: aggregate.effectiveTargetAttribution
            )
        }
    }

    /// Coalesces indistinguishable declarations into one exact dependency name
    /// while retaining every declaration origin and all proven target evidence.
    public func aggregateDirectDependencies(
        _ declarations: [CocoaPodDependency]
    ) -> [CocoaPodDependency] {
        var orderedNames: [String] = []
        var declarationsByName: [String: [CocoaPodDependency]] = [:]

        for declaration in declarations {
            if declarationsByName[declaration.name] == nil {
                orderedNames.append(declaration.name)
            }
            declarationsByName[declaration.name, default: []].append(declaration)
        }

        return orderedNames.compactMap { name in
            guard let matching = declarationsByName[name],
                  let first = matching.first else {
                return nil
            }

            let origins = matching
                .flatMap { $0.declarations ?? [] }
                .sorted { lhs, rhs in
                    if lhs.line == rhs.line {
                        return lhs.scope.rawValue < rhs.scope.rawValue
                    }
                    return lhs.line < rhs.line
                }
            let targets = Array(Set(matching.flatMap(\.targets))).sorted()
            // A helper declaration keeps its one literal source origin even
            // when several call sites prove several targets. Attribution,
            // rather than a duplicated origin per call site, carries that
            // evidence and determines whether the declaration is unresolved.
            let unresolvedCount = matching.reduce(into: 0) { count, declaration in
                let attribution = declaration.effectiveTargetAttribution
                switch attribution.status {
                case .exact, .multiple:
                    break
                case .partial, .unresolved:
                    count += max(attribution.unresolvedDeclarationCount, 1)
                }
            }
            let attribution = makeAttribution(
                targets: targets,
                unresolvedCount: unresolvedCount,
                declarations: origins
            )

            let versions = Array(Set(matching.compactMap(\.version))).sorted()
            let version = versions.count == 1 ? versions[0] : nil
            let source = matching.dropFirst().allSatisfy { $0.source == first.source }
                ? first.source
                : .unknown

            return CocoaPodDependency(
                name: name,
                version: version,
                source: source,
                isDirect: true,
                targets: targets,
                declarations: origins.isEmpty ? nil : origins,
                targetAttribution: attribution
            )
        }
    }

    private func makeAttribution(
        targets: [String],
        unresolvedCount: Int,
        declarations: [PodfileDeclaration]
    ) -> TargetAttribution {
        if unresolvedCount == 0, targets.count == 1 {
            return TargetAttribution(status: .exact, targets: targets)
        }
        if unresolvedCount == 0, targets.count > 1 {
            return TargetAttribution(
                status: .multiple,
                targets: targets,
                reason: "Multiple statically proven Podfile targets: \(targets.joined(separator: ", "))."
            )
        }
        if !targets.isEmpty {
            return TargetAttribution(
                status: .partial,
                targets: targets,
                unresolvedDeclarationCount: unresolvedCount,
                reason: "Static target evidence is partial: \(targets.joined(separator: ", ")); \(unresolvedCount) declaration(s) unresolved."
            )
        }

        let helperNames = Array(Set(declarations.compactMap { declaration -> String? in
            declaration.scope == .rubyHelper ? declaration.scopeName : nil
        })).sorted()
        let reason: String
        if !helperNames.isEmpty {
            reason = "Declaration(s) originate in Ruby helper(s) \(helperNames.joined(separator: ", ")); call-site targets are not statically proven."
        } else if declarations.contains(where: { $0.scope == .abstractTarget }) {
            reason = "Declaration(s) originate in an abstract target, not one proven Xcode target."
        } else if declarations.contains(where: { $0.scope == .dynamicScope }) {
            reason = "Declaration target is obscured by unsupported dynamic Ruby scope."
        } else {
            reason = "No destination target is proven from static Podfile structure."
        }
        return TargetAttribution(
            status: .unresolved,
            unresolvedDeclarationCount: unresolvedCount,
            reason: reason
        )
    }
}
