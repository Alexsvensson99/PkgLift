// PkgLiftCocoaPods/PodfileParser.swift
// Static parser for Podfile.

import Foundation
import PkgLiftCore

/// Statically parses a Podfile without executing Ruby.
public struct PodfileParser: Sendable {
    public enum Error: Swift.Error {
        case fileReadFailed(URL)
    }

    public init() {}

    /// Parses a Podfile from file URL.
    public func parse(fileURL: URL) throws -> (features: PodfileFeatures, directDependencies: [CocoaPodDependency], targets: [String]) {
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw Error.fileReadFailed(fileURL)
        }
        return parse(content: content)
    }

    /// Parses a Podfile from string content.
    public func parse(content: String) -> (features: PodfileFeatures, directDependencies: [CocoaPodDependency], targets: [String]) {
        var features = PodfileFeatures()
        var directDependencies: [CocoaPodDependency] = []
        var targets: [String] = []
        var scopes: [StaticScope] = []

        let lines = content.components(separatedBy: .newlines)
        let targetAnalysis = analyzeTargetInheritance(lines: lines)
        let helperAnalysis = analyzeHelpers(lines: lines, targetAnalysis: targetAnalysis)

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let integrationDirectives: [(String, ProjectIntegration)] = [
                ("use_react_native!", .reactNative),
                ("flutter_install_all_ios_pods", .flutter),
                ("capacitor_pods", .capacitor),
            ]
            for (directive, integration) in integrationDirectives
            where PodfileStaticSyntax.isDirectiveInvocation(directive, in: trimmed) {
                if !features.integrationMarkers.contains(integration) {
                    features.integrationMarkers.append(integration)
                    features.integrationMarkers.sort()
                }
            }

            if trimmed.contains("use_frameworks!") {
                features.useFrameworks = true
            }
            if trimmed.contains("use_modular_headers!") {
                features.useModularHeaders = true
            }
            if trimmed.contains("inherit! :search_paths") {
                features.hasInheritSearchPaths = true
            }
            if trimmed.contains("post_install") {
                features.hasPostInstallHook = true
            }
            if trimmed.contains("pre_install") {
                features.hasPreInstallHook = true
            }
            if trimmed.contains("script_phase") {
                features.hasScriptPhase = true
            }

            // Conservative detection for Ruby constructs whose control flow or
            // values this static parser cannot prove. Any such construct keeps
            // migration out of AUTO.
            let dynamicPrefixes = [
                "def ", "if ", "unless ", "case ", "for ", "while ", "until ",
                "class ", "module ", "begin", "plugin ", "install!",
            ]
            let hasUnknownBlock = trimmed.range(
                of: #"\bdo(?:\s*\|.*\|)?\s*$"#,
                options: .regularExpression
            ) != nil
                && !trimmed.hasPrefix("target ")
                && !trimmed.hasPrefix("abstract_target ")
                && !trimmed.hasPrefix("post_install ")
                && !trimmed.hasPrefix("pre_install ")
            let hasVariableAssignment = trimmed.range(
                of: #"^[a-zA-Z_]\w*\s*=(?!=)"#,
                options: .regularExpression
            ) != nil
            let hasDynamicPrefix = dynamicPrefixes.contains(where: { prefix in
                guard trimmed.hasPrefix(prefix) else { return false }
                return prefix != "def "
                    || !helperAnalysis.eligibleDefinitionLines.contains(offset)
            })
            if hasDynamicPrefix
                || hasUnknownBlock
                || hasVariableAssignment
                || helperAnalysis.dynamicLines.contains(offset)
                || trimmed.contains("require ")
                || trimmed.contains("#{")
                || trimmed.contains("eval(")
                || trimmed.contains("system(")
                || trimmed.contains("exec(")
                || trimmed.contains("%x{")
                || trimmed.contains("`") {
                features.hasDynamicRuby = true
            }

            if trimmed.hasPrefix("abstract_target") {
                features.hasAbstractTargets = true
            }

            if isEnd(trimmed) {
                if !scopes.isEmpty {
                    scopes.removeLast()
                }
                continue
            }

            if let targetName = targetName(from: trimmed, keyword: "target") {
                scopes.append(.target(targetName, line: offset))
                if !targets.contains(targetName) {
                    targets.append(targetName)
                }
                continue
            }

            if let abstractTargetName = targetName(from: trimmed, keyword: "abstract_target") {
                scopes.append(.abstractTarget(abstractTargetName))
                continue
            }

            if trimmed.hasPrefix("def ") {
                if let helperName = firstCapture(
                    in: trimmed,
                    pattern: #"^def\s+([A-Za-z_]\w*[!?=]?)"#
                ) {
                    scopes.append(.rubyHelper(helperName))
                } else {
                    scopes.append(.dynamic)
                }
                continue
            }

            let parsedPodName = PodfileStaticSyntax.podName(from: trimmed)
            if PodfileStaticSyntax.isPodDeclaration(trimmed), parsedPodName == nil {
                features.hasDynamicRuby = true
            }
            if let name = parsedPodName {
                let parsedSource = podSource(from: trimmed)
                let source = isRepresentablePodDeclaration(trimmed) || parsedSource != .registry
                    ? parsedSource
                    : .unknown
                let resolution = targetResolution(
                    for: scopes,
                    targetAnalysis: targetAnalysis
                )
                let exactTarget = !resolution.hasUnresolvedTargets && resolution.targets.count == 1
                    ? resolution.targets.first
                    : nil
                let declaration = declarationEvidence(
                    line: offset + 1,
                    scopes: scopes,
                    source: source,
                    targetName: exactTarget
                )
                let targetNames = resolution.targets
                let attribution = targetAttribution(
                    for: resolution,
                    declaration: declaration
                )
                directDependencies.append(CocoaPodDependency(
                    name: name,
                    version: nil,
                    source: source,
                    isDirect: true,
                    targets: targetNames,
                    declarations: [declaration],
                    targetAttribution: attribution
                ))
            }

            if opensGenericBlock(trimmed) {
                scopes.append(.dynamic)
            }
        }

        directDependencies = directDependencies.map { dependency in
            guard let declaration = dependency.declarations?.first,
                  declaration.scope == .rubyHelper,
                  let helperName = declaration.scopeName,
                  let resolution = helperAnalysis.resolutions[helperName] else {
                return dependency
            }

            let declarations = dependency.declarations?.map { origin in
                let exactTarget = resolution.attribution.status == .exact
                    ? resolution.targets.first
                    : nil
                return PodfileDeclaration(
                    line: origin.line,
                    scope: origin.scope,
                    scopeName: origin.scopeName,
                    targetName: exactTarget,
                    source: origin.source
                )
            }

            return CocoaPodDependency(
                name: dependency.name,
                version: dependency.version,
                source: dependency.source,
                isDirect: dependency.isDirect,
                targets: resolution.targets,
                declarations: declarations,
                targetAttribution: resolution.attribution
            )
        }

        return (features, directDependencies, targets)
    }

    private func analyzeTargetInheritance(lines: [String]) -> TargetAnalysis {
        var nodes: [Int: TargetNode] = [:]
        var scopes: [TargetStructureScope] = []

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if isEnd(trimmed) {
                if !scopes.isEmpty { scopes.removeLast() }
                continue
            }

            if trimmed.hasPrefix("def ") {
                scopes.append(.opaque)
                continue
            }

            if let name = targetName(from: trimmed, keyword: "target") {
                let parent = nearestTargetLine(in: scopes)
                let isProven = !scopes.contains(where: { scope in
                    switch scope {
                    case .dynamic, .opaque:
                        return true
                    case .target, .abstractTarget:
                        return false
                    }
                })
                nodes[offset] = TargetNode(
                    name: name,
                    parentLine: parent,
                    isProven: isProven
                )
                scopes.append(.target(offset))
                continue
            }

            if targetName(from: trimmed, keyword: "abstract_target") != nil {
                scopes.append(.abstractTarget)
                continue
            }

            if trimmed.hasPrefix("inherit!") {
                guard let targetLine = nearestTargetLine(in: scopes),
                      var node = nodes[targetLine] else {
                    continue
                }
                let hasUncertainScope = hasUncertainScope(
                    afterTargetLine: targetLine,
                    scopes: scopes
                )
                let mode: TargetInheritance
                if hasUncertainScope {
                    mode = .unknown
                } else if let value = firstCapture(
                    in: trimmed,
                    pattern: #"^inherit!\s+:(search_paths|none|complete)\s*(?:#.*)?$"#
                ) {
                    mode = value == "complete" ? .inherits : .excludes
                } else {
                    mode = .unknown
                }

                if let existing = node.explicitInheritance, existing != mode {
                    node.explicitInheritance = .unknown
                } else {
                    node.explicitInheritance = mode
                }
                nodes[targetLine] = node
                continue
            }

            if trimmed.hasPrefix("target ") || trimmed.hasPrefix("abstract_target ") {
                if let targetLine = nearestTargetLine(in: scopes), var node = nodes[targetLine] {
                    node.hasUnknownDescendants = true
                    nodes[targetLine] = node
                }
            }

            if opensGenericBlock(trimmed) {
                scopes.append(.dynamic)
            }
        }

        var childrenByParent: [Int: [Int]] = [:]
        for (line, node) in nodes {
            if let parent = node.parentLine {
                childrenByParent[parent, default: []].append(line)
            }
        }
        for parent in Array(childrenByParent.keys) {
            childrenByParent[parent] = childrenByParent[parent]?.sorted()
        }

        var cache: [Int: StaticTargetResolution] = [:]
        func resolve(_ line: Int) -> StaticTargetResolution {
            if let cached = cache[line] { return cached }
            guard let node = nodes[line], node.isProven else {
                return StaticTargetResolution(targets: [], hasUnresolvedTargets: true)
            }

            var targets: Set<String> = [node.name]
            var hasUnresolvedTargets = node.hasUnknownDescendants
            for childLine in childrenByParent[line] ?? [] {
                guard let child = nodes[childLine] else {
                    hasUnresolvedTargets = true
                    continue
                }
                switch child.explicitInheritance ?? .inherits {
                case .inherits:
                    let childResolution = resolve(childLine)
                    targets.formUnion(childResolution.targets)
                    hasUnresolvedTargets = hasUnresolvedTargets
                        || childResolution.hasUnresolvedTargets
                case .excludes:
                    break
                case .unknown:
                    hasUnresolvedTargets = true
                }
            }

            let resolution = StaticTargetResolution(
                targets: Array(targets).sorted(),
                hasUnresolvedTargets: hasUnresolvedTargets
            )
            cache[line] = resolution
            return resolution
        }

        for line in nodes.keys.sorted() {
            _ = resolve(line)
        }
        return TargetAnalysis(resolutionsByLine: cache)
    }

    private func nearestTargetLine(in scopes: [TargetStructureScope]) -> Int? {
        scopes.reversed().compactMap { scope -> Int? in
            if case .target(let line) = scope { return line }
            return nil
        }.first
    }

    private func hasUncertainScope(
        afterTargetLine targetLine: Int,
        scopes: [TargetStructureScope]
    ) -> Bool {
        for scope in scopes.reversed() {
            switch scope {
            case .target(let line):
                if line == targetLine { return false }
            case .dynamic, .opaque:
                return true
            case .abstractTarget:
                continue
            }
        }
        return true
    }

    /// Performs a deliberately small static analysis of Ruby helpers. It does
    /// not execute Ruby and does not follow helper-to-helper calls.
    private func analyzeHelpers(
        lines: [String],
        targetAnalysis: TargetAnalysis
    ) -> HelperAnalysis {
        var definitions: [HelperDefinition] = []
        var executableLines: [HelperExecutableLine] = []
        var scopes: [HelperScope] = []

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if isEnd(trimmed) {
                if !scopes.isEmpty {
                    scopes.removeLast()
                }
                continue
            }

            if let target = targetName(from: trimmed, keyword: "target") {
                markContainingHelperUnsupported(scopes: scopes, definitions: &definitions)
                scopes.append(.target(target, line: offset))
                continue
            }

            if let abstractTarget = targetName(from: trimmed, keyword: "abstract_target") {
                markContainingHelperUnsupported(scopes: scopes, definitions: &definitions)
                scopes.append(.abstractTarget(abstractTarget))
                continue
            }

            if trimmed.hasPrefix("def ") {
                markContainingHelperUnsupported(scopes: scopes, definitions: &definitions)
                let name = firstCapture(
                    in: trimmed,
                    pattern: #"^def\s+([A-Za-z_]\w*)"#
                )
                let isParameterless = trimmed.range(
                    of: #"^def\s+[A-Za-z_]\w*\s*(?:\(\s*\))?\s*(?:#.*)?$"#,
                    options: .regularExpression
                ) != nil
                let definitionIndex = definitions.count
                definitions.append(HelperDefinition(
                    name: name,
                    line: offset,
                    isParameterless: isParameterless,
                    isTopLevel: scopes.isEmpty,
                    hasUnsupportedBody: false
                ))
                scopes.append(.helper(definitionIndex))
                continue
            }

            if isLiteralPodDeclaration(trimmed) {
                continue
            }

            if isStaticHelperDirective(trimmed) {
                continue
            }

            markContainingHelperUnsupported(scopes: scopes, definitions: &definitions)
            executableLines.append(HelperExecutableLine(
                line: offset,
                code: rubyCodeBeforeComment(trimmed),
                scopes: scopes
            ))

            if opensGenericBlock(trimmed) {
                scopes.append(.dynamic)
            }
        }

        let definitionsByName = Dictionary(grouping: definitions.indices.compactMap { index -> (String, Int)? in
            guard let name = definitions[index].name else { return nil }
            return (name, index)
        }, by: { $0.0 })
        let helperNames = Set(definitionsByName.keys)
        var evidence = Dictionary(
            uniqueKeysWithValues: helperNames.map { ($0, HelperCallEvidence()) }
        )
        var dynamicLines: Set<Int> = []

        for executable in executableLines {
            let dispatch = helperDispatchEvidence(in: executable.code)
            if dispatch.hasUnknownTarget {
                for helperName in helperNames {
                    evidence[helperName]?.hasUnresolvedUsage = true
                }
                dynamicLines.insert(executable.line)
                continue
            }
            if !dispatch.literalTargets.isEmpty {
                dynamicLines.insert(executable.line)
                for helperName in dispatch.literalTargets where helperNames.contains(helperName) {
                    evidence[helperName]?.hasUnresolvedUsage = true
                }
            }

            let simpleName = simpleHelperInvocationName(from: executable.code)
            if let simpleName, helperNames.contains(simpleName) {
                let resolution = targetResolution(
                    for: executable.scopes,
                    targetAnalysis: targetAnalysis
                )
                evidence[simpleName]?.targets.formUnion(resolution.targets)
                if resolution.hasUnresolvedTargets || resolution.targets.isEmpty {
                    evidence[simpleName]?.hasUnresolvedUsage = true
                }
                continue
            }

            for helperName in helperNames where referencesHelper(
                helperName,
                in: executable.code
            ) {
                evidence[helperName]?.hasUnresolvedUsage = true
                dynamicLines.insert(executable.line)
            }
        }

        var resolutions: [String: HelperResolution] = [:]
        var eligibleDefinitionLines: Set<Int> = []

        for helperName in helperNames.sorted() {
            let matching = definitionsByName[helperName] ?? []
            let indices = matching.map { $0.1 }
            let eligible = indices.count == 1
                && indices.allSatisfy { index in
                    let definition = definitions[index]
                    return definition.isParameterless
                        && definition.isTopLevel
                        && !definition.hasUnsupportedBody
                }

            guard eligible, let index = indices.first else {
                for index in indices {
                    dynamicLines.insert(definitions[index].line)
                }
                resolutions[helperName] = HelperResolution(
                    targets: [],
                    attribution: TargetAttribution(
                        status: .unresolved,
                        unresolvedDeclarationCount: 1,
                        reason: helperRejectionReason(indices: indices, definitions: definitions)
                    )
                )
                continue
            }

            eligibleDefinitionLines.insert(definitions[index].line)
            let callEvidence = evidence[helperName] ?? HelperCallEvidence()
            let targets = Array(callEvidence.targets).sorted()
            let hasUnresolvedUsage = callEvidence.hasUnresolvedUsage
            let attribution: TargetAttribution

            if hasUnresolvedUsage, !targets.isEmpty {
                attribution = TargetAttribution(
                    status: .partial,
                    targets: targets,
                    unresolvedDeclarationCount: 1,
                    reason: "Helper '\(helperName)' has proven target call sites and unsupported or unresolved call sites."
                )
            } else if hasUnresolvedUsage || targets.isEmpty {
                attribution = TargetAttribution(
                    status: .unresolved,
                    unresolvedDeclarationCount: 1,
                    reason: targets.isEmpty
                        ? "Helper '\(helperName)' has no call site in one proven literal target."
                        : "Helper '\(helperName)' call-site target is unresolved."
                )
            } else if targets.count == 1 {
                attribution = TargetAttribution(status: .exact, targets: targets)
            } else {
                attribution = TargetAttribution(
                    status: .multiple,
                    targets: targets,
                    reason: "Helper '\(helperName)' is called from multiple statically proven Podfile targets: \(targets.joined(separator: ", "))."
                )
            }

            resolutions[helperName] = HelperResolution(
                targets: targets,
                attribution: attribution
            )
        }

        return HelperAnalysis(
            resolutions: resolutions,
            eligibleDefinitionLines: eligibleDefinitionLines,
            dynamicLines: dynamicLines
        )
    }

    private func markContainingHelperUnsupported(
        scopes: [HelperScope],
        definitions: inout [HelperDefinition]
    ) {
        guard let index = scopes.reversed().compactMap({ scope -> Int? in
            if case .helper(let index) = scope { return index }
            return nil
        }).first else {
            return
        }
        definitions[index].hasUnsupportedBody = true
    }

    private func isStaticHelperDirective(_ line: String) -> Bool {
        let noArgumentPatterns = [
            #"^use_modular_headers!\s*(?:\(\s*\))?\s*(?:#.*)?$"#,
            #"^inhibit_all_warnings!\s*(?:\(\s*\))?\s*(?:#.*)?$"#,
            #"^use_frameworks!\s*(?:\(\s*\))?\s*(?:#.*)?$"#,
        ]
        if noArgumentPatterns.contains(where: { pattern in
            line.range(of: pattern, options: .regularExpression) != nil
        }) {
            return true
        }

        let staticLinkage = #"(?::linkage\s*=>\s*:(?:static|dynamic)|linkage:\s*:(?:static|dynamic))"#
        let argumentPatterns = [
            #"^use_frameworks!\s+\#(staticLinkage)\s*(?:#.*)?$"#,
            #"^use_frameworks!\s*\(\s*\#(staticLinkage)\s*\)\s*(?:#.*)?$"#,
        ]
        return argumentPatterns.contains(where: { pattern in
            line.range(of: pattern, options: .regularExpression) != nil
        })
    }

    private func helperDispatchEvidence(in code: String) -> HelperDispatchEvidence {
        guard let expression = try? NSRegularExpression(
            pattern: #"\b(send|public_send|method|__send__)\b"#
        ) else {
            return HelperDispatchEvidence()
        }
        let searchRange = NSRange(code.startIndex..<code.endIndex, in: code)
        var result = HelperDispatchEvidence()

        for match in expression.matches(in: code, range: searchRange) {
            guard let nameRange = Range(match.range(at: 1), in: code) else { continue }
            let dispatchName = String(code[nameRange])
            if dispatchName == "__send__" {
                result.hasUnknownTarget = true
                continue
            }

            var cursor = nameRange.upperBound
            while cursor < code.endIndex, code[cursor].isWhitespace {
                cursor = code.index(after: cursor)
            }

            if cursor == code.endIndex {
                continue
            }

            if cursor < code.endIndex, code[cursor] == "(" {
                cursor = code.index(after: cursor)
                while cursor < code.endIndex, code[cursor].isWhitespace {
                    cursor = code.index(after: cursor)
                }
            }

            guard cursor < code.endIndex else {
                result.hasUnknownTarget = true
                continue
            }

            if code[cursor] == ":" {
                cursor = code.index(after: cursor)
                let start = cursor
                while cursor < code.endIndex,
                      (code[cursor].isLetter || code[cursor].isNumber || code[cursor] == "_") {
                    cursor = code.index(after: cursor)
                }
                let literal = String(code[start..<cursor])
                if isPlainHelperName(literal) {
                    result.literalTargets.insert(literal)
                } else {
                    result.hasUnknownTarget = true
                }
                continue
            }

            if code[cursor] == "'" || code[cursor] == "\"" {
                let quote = code[cursor]
                cursor = code.index(after: cursor)
                let start = cursor
                while cursor < code.endIndex, code[cursor] != quote {
                    cursor = code.index(after: cursor)
                }
                let literal = String(code[start..<cursor])
                if cursor < code.endIndex, isPlainHelperName(literal) {
                    result.literalTargets.insert(literal)
                } else {
                    result.hasUnknownTarget = true
                }
                continue
            }

            result.hasUnknownTarget = true
        }

        return result
    }

    private func isPlainHelperName(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z_]\w*$"#,
            options: .regularExpression
        ) != nil
    }

    private func isLiteralPodDeclaration(_ line: String) -> Bool {
        guard PodfileStaticSyntax.podName(from: line) != nil else {
            return false
        }
        let code = rubyCodeOutsideStrings(line)
        guard !code.contains(";"),
              !opensGenericBlock(line),
              code.range(of: #"\b(?:if|unless)\b"#, options: .regularExpression) == nil,
              !line.contains("#{"),
              !line.contains("eval("),
              !line.contains("system("),
              !line.contains("exec("),
              !line.contains("%x{"),
              !line.contains("`") else {
            return false
        }

        guard let expression = try? NSRegularExpression(pattern: #"[A-Za-z_]\w*"#) else {
            return false
        }
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        return expression.matches(in: code, range: range).allSatisfy { match in
            guard let tokenRange = Range(match.range, in: code) else { return false }
            let token = String(code[tokenRange])
            if token == "pod" || token == "true" || token == "false" || token == "nil" {
                return true
            }
            let preceding = tokenRange.lowerBound == code.startIndex
                ? nil
                : code[code.index(before: tokenRange.lowerBound)]
            let following = tokenRange.upperBound == code.endIndex
                ? nil
                : code[tokenRange.upperBound]
            return preceding == ":" || following == ":"
        }
    }

    private func isRepresentablePodDeclaration(_ line: String) -> Bool {
        PodfileStaticSyntax.representablePodName(from: line) != nil
    }

    private func simpleHelperInvocationName(from code: String) -> String? {
        firstCapture(
            in: code,
            pattern: #"^\s*([A-Za-z_]\w*)\s*(?:\(\s*\))?\s*$"#
        )
    }

    private func targetResolution(
        for scopes: [HelperScope],
        targetAnalysis: TargetAnalysis
    ) -> StaticTargetResolution {
        if scopes.contains(where: { scope in
            switch scope {
            case .helper, .dynamic:
                return true
            case .target, .abstractTarget:
                return false
            }
        }) {
            return StaticTargetResolution(targets: [], hasUnresolvedTargets: true)
        }

        for scope in scopes.reversed() {
            switch scope {
            case .target(_, let line):
                return targetAnalysis.resolutionsByLine[line]
                    ?? StaticTargetResolution(targets: [], hasUnresolvedTargets: true)
            case .abstractTarget:
                return StaticTargetResolution(targets: [], hasUnresolvedTargets: true)
            case .helper, .dynamic:
                return StaticTargetResolution(targets: [], hasUnresolvedTargets: true)
            }
        }
        return StaticTargetResolution(targets: [], hasUnresolvedTargets: true)
    }

    private func targetResolution(
        for scopes: [StaticScope],
        targetAnalysis: TargetAnalysis
    ) -> StaticTargetResolution {
        let hasDynamicScope = scopes.contains(where: { scope in
            if case .dynamic = scope { return true }
            return false
        })

        for scope in scopes.reversed() {
            switch scope {
            case .target(_, let line):
                let resolution = targetAnalysis.resolutionsByLine[line]
                    ?? StaticTargetResolution(targets: [], hasUnresolvedTargets: true)
                return StaticTargetResolution(
                    targets: resolution.targets,
                    hasUnresolvedTargets: resolution.hasUnresolvedTargets || hasDynamicScope
                )
            case .abstractTarget, .rubyHelper:
                return StaticTargetResolution(targets: [], hasUnresolvedTargets: true)
            case .dynamic:
                continue
            }
        }
        return StaticTargetResolution(targets: [], hasUnresolvedTargets: true)
    }

    private func targetAttribution(
        for resolution: StaticTargetResolution,
        declaration: PodfileDeclaration
    ) -> TargetAttribution {
        if resolution.hasUnresolvedTargets, !resolution.targets.isEmpty {
            return TargetAttribution(
                status: .partial,
                targets: resolution.targets,
                unresolvedDeclarationCount: 1,
                reason: "Nested target inheritance is only partially proven."
            )
        }
        if resolution.hasUnresolvedTargets || resolution.targets.isEmpty {
            return TargetAttribution(
                status: .unresolved,
                unresolvedDeclarationCount: 1,
                reason: unresolvedReason(for: declaration)
            )
        }
        if resolution.targets.count == 1 {
            return TargetAttribution(status: .exact, targets: resolution.targets)
        }
        return TargetAttribution(
            status: .multiple,
            targets: resolution.targets,
            reason: "Declaration applies to a parent target and inheriting nested targets: \(resolution.targets.joined(separator: ", "))."
        )
    }

    private func referencesHelper(_ name: String, in code: String) -> Bool {
        let codeWithoutStrings = rubyCodeOutsideStrings(code)
        if codeWithoutStrings.range(
            of: #"\b\#(NSRegularExpression.escapedPattern(for: name))\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        return code.range(
            of: #"\b(?:send|public_send|method)\s*(?:\(\s*)?['\"]\#(escapedName)['\"]"#,
            options: .regularExpression
        ) != nil
    }

    private func rubyCodeBeforeComment(_ line: String) -> String {
        var result = ""
        var quote: Character?
        var escaped = false

        for character in line {
            if escaped {
                result.append(character)
                escaped = false
                continue
            }
            if character == "\\", quote != nil {
                result.append(character)
                escaped = true
                continue
            }
            if let activeQuote = quote {
                result.append(character)
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                result.append(character)
            } else if character == "#" {
                break
            } else {
                result.append(character)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rubyCodeOutsideStrings(_ line: String) -> String {
        var result = ""
        var quote: Character?
        var escaped = false

        for character in line {
            if escaped {
                escaped = false
                continue
            }
            if character == "\\", quote != nil {
                escaped = true
                continue
            }
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                result.append(" ")
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                result.append(" ")
            } else if character == "#" {
                break
            } else {
                result.append(character)
            }
        }
        return result
    }

    private func helperRejectionReason(
        indices: [Int],
        definitions: [HelperDefinition]
    ) -> String {
        if indices.count > 1 {
            return "Ruby helper has multiple definitions; dispatch is ambiguous."
        }
        guard let index = indices.first else {
            return "Ruby helper definition is not statically identifiable."
        }
        let definition = definitions[index]
        if !definition.isParameterless {
            return "Ruby helper has parameters or an unsupported signature."
        }
        if !definition.isTopLevel {
            return "Ruby helper definition scope is not unambiguously top-level."
        }
        return "Ruby helper body contains recursion, dispatch, or unsupported Ruby statements."
    }

    private func targetName(from line: String, keyword: String) -> String? {
        switch keyword {
        case "target":
            return PodfileStaticSyntax.targetName(from: line)
        case "abstract_target":
            return PodfileStaticSyntax.abstractTargetName(from: line)
        default:
            return nil
        }
    }
    private func declarationEvidence(
        line: Int,
        scopes: [StaticScope],
        source: PodSource,
        targetName: String?
    ) -> PodfileDeclaration {
        for scope in scopes.reversed() {
            if case .rubyHelper(let name) = scope {
                return PodfileDeclaration(
                    line: line,
                    scope: .rubyHelper,
                    scopeName: name,
                    source: source
                )
            }
        }

        for scope in scopes.reversed() {
            switch scope {
            case .target(let name, _):
                return PodfileDeclaration(
                    line: line,
                    scope: .target,
                    scopeName: name,
                    targetName: targetName,
                    source: source
                )
            case .abstractTarget(let name):
                return PodfileDeclaration(
                    line: line,
                    scope: .abstractTarget,
                    scopeName: name,
                    source: source
                )
            case .rubyHelper, .dynamic:
                continue
            }
        }

        if scopes.contains(where: { scope in
            if case .dynamic = scope { return true }
            return false
        }) {
            return PodfileDeclaration(line: line, scope: .dynamicScope, source: source)
        }

        return PodfileDeclaration(line: line, scope: .topLevel, source: source)
    }

    private func unresolvedReason(for declaration: PodfileDeclaration) -> String? {
        switch declaration.scope {
        case .target:
            return nil
        case .rubyHelper:
            let name = declaration.scopeName ?? "unknown"
            return "Declaration originates in Ruby helper '\(name)'; call-site targets are not statically proven."
        case .abstractTarget:
            return "Declaration originates in an abstract target, not one proven Xcode target."
        case .dynamicScope:
            return "Declaration target is obscured by unsupported dynamic Ruby scope."
        case .topLevel:
            return "Top-level declaration has no explicit target."
        }
    }

    private func podSource(from line: String) -> PodSource {
        if let gitURL = firstCapture(
            in: line,
            pattern: #":git\s*=>\s*['\"]([^'\"]+)['\"]"#
        ) ?? firstCapture(
            in: line,
            pattern: #"\bgit:\s*['\"]([^'\"]+)['\"]"#
        ) {
            let ref: GitRef?
            if let branch = optionValue(named: "branch", in: line) {
                ref = .branch(branch)
            } else if let tag = optionValue(named: "tag", in: line) {
                ref = .tag(tag)
            } else if let commit = optionValue(named: "commit", in: line) {
                ref = .commit(commit)
            } else {
                ref = nil
            }
            return .git(url: gitURL, ref: ref)
        }

        if let path = optionValue(named: "path", in: line) {
            return .path(path)
        }
        return .registry
    }

    private func optionValue(named name: String, in line: String) -> String? {
        firstCapture(
            in: line,
            pattern: #":\#(name)\s*=>\s*['\"]([^'\"]+)['\"]"#
        ) ?? firstCapture(
            in: line,
            pattern: #"\b\#(name):\s*['\"]([^'\"]+)['\"]"#
        )
    }

    private func firstCapture(in value: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[captureRange])
    }

    private func isEnd(_ line: String) -> Bool {
        line.range(of: #"^end\b"#, options: .regularExpression) != nil
    }

    private func opensGenericBlock(_ line: String) -> Bool {
        if line.range(
            of: #"\bdo(?:\s*\|.*\|)?\s*$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        let prefixes = [
            "if ", "unless ", "case ", "for ", "while ", "until ",
            "class ", "module ", "begin",
        ]
        return prefixes.contains(where: { line.hasPrefix($0) })
    }
}

private enum StaticScope {
    case target(String, line: Int)
    case abstractTarget(String)
    case rubyHelper(String)
    case dynamic
}

private struct HelperAnalysis {
    let resolutions: [String: HelperResolution]
    let eligibleDefinitionLines: Set<Int>
    let dynamicLines: Set<Int>
}

private struct HelperResolution {
    let targets: [String]
    let attribution: TargetAttribution
}

private struct HelperDefinition {
    let name: String?
    let line: Int
    let isParameterless: Bool
    let isTopLevel: Bool
    var hasUnsupportedBody: Bool
}

private struct HelperExecutableLine {
    let line: Int
    let code: String
    let scopes: [HelperScope]
}

private struct HelperCallEvidence {
    var targets: Set<String> = []
    var hasUnresolvedUsage = false
}

private struct HelperDispatchEvidence {
    var literalTargets: Set<String> = []
    var hasUnknownTarget = false
}

private enum HelperScope {
    case target(String, line: Int)
    case abstractTarget(String)
    case helper(Int)
    case dynamic
}

private struct TargetAnalysis {
    let resolutionsByLine: [Int: StaticTargetResolution]
}

private struct StaticTargetResolution {
    let targets: [String]
    let hasUnresolvedTargets: Bool
}

private struct TargetNode {
    let name: String
    let parentLine: Int?
    let isProven: Bool
    var explicitInheritance: TargetInheritance? = nil
    var hasUnknownDescendants = false
}

private enum TargetInheritance: Equatable {
    case inherits
    case excludes
    case unknown
}

private enum TargetStructureScope {
    case target(Int)
    case abstractTarget
    case dynamic
    case opaque
}
