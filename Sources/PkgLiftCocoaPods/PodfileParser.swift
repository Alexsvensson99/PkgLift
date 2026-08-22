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

    private static let modeledDSLHelperNames: Set<String> = [
        "pod", "target", "abstract_target", "platform", "source", "workspace", "project",
    ]
    private static let maxStaticScopeNestingDepth = 256

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
        var seenTargets: Set<String> = []
        var scopes: [StaticScope] = []

        let lexicalAnalysis = sanitizedLinesForStaticAnalysis(
            rubyPhysicalLines(in: content)
        )
        let lines = lexicalAnalysis.lines
        if lexicalAnalysis.hasUnsupportedStructure {
            features.hasDynamicRuby = true
        }
        let targetAnalysis = analyzeTargetInheritance(lines: lines)
        if targetAnalysis.hasUnsupportedNesting {
            features.hasDynamicRuby = true
        }
        let usesConservativeFlatParsing = targetAnalysis.hasUnsupportedNesting
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
            let hasUnknownBlock = opensGenericBlock(trimmed)
                && PodfileStaticSyntax.targetName(from: trimmed) == nil
                && PodfileStaticSyntax.abstractTargetName(from: trimmed) == nil
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
            let hasUnmodeledStatement = !isStaticallyModeledStatement(
                trimmed,
                line: offset,
                helperAnalysis: helperAnalysis
            )
            if hasDynamicPrefix
                || hasUnknownBlock
                || hasVariableAssignment
                || hasUnmodeledStatement
                || helperAnalysis.dynamicLines.contains(offset)
                || trimmed.contains("require ")
                || trimmed.contains("#{")
                || trimmed.contains("eval(")
                || trimmed.contains("system(")
                || trimmed.contains("exec(")
                || trimmed.contains("%x{")
                || containsHeredocOpener(trimmed)
                || containsUnsupportedBraceSyntax(trimmed)
                || trimmed.contains("`") {
                features.hasDynamicRuby = true
            }

            if trimmed.hasPrefix("abstract_target") {
                features.hasAbstractTargets = true
            }

            if isEnd(trimmed) {
                if usesConservativeFlatParsing {
                    continue
                } else if scopes.isEmpty {
                    features.hasDynamicRuby = true
                } else {
                    scopes.removeLast()
                }
                continue
            }

            if let targetName = targetName(from: trimmed, keyword: "target") {
                if !usesConservativeFlatParsing {
                    scopes.append(.target(targetName, line: offset))
                }
                if seenTargets.insert(targetName).inserted {
                    targets.append(targetName)
                }
                continue
            }

            if let abstractTargetName = targetName(from: trimmed, keyword: "abstract_target") {
                if !usesConservativeFlatParsing {
                    scopes.append(.abstractTarget(abstractTargetName))
                }
                continue
            }

            if trimmed.hasPrefix("def ") {
                if !usesConservativeFlatParsing {
                    if let helperName = firstCapture(
                        in: trimmed,
                        pattern: #"^def\s+([A-Za-z_]\w*[!?=]?)"#
                    ) {
                        scopes.append(.rubyHelper(helperName))
                    } else {
                        scopes.append(.dynamic)
                    }
                }
                continue
            }

            let parsedPodName = PodfileStaticSyntax.podName(from: trimmed)
            if PodfileStaticSyntax.isPodDeclaration(trimmed), parsedPodName == nil {
                features.hasDynamicRuby = true
            }
            if let name = parsedPodName {
                let parsedSource = parsedPodSource(from: trimmed)
                let source = isRepresentablePodDeclaration(trimmed)
                    || parsedSource.source != .registry
                    || parsedSource.sourceProvenance != nil
                    ? parsedSource.source
                    : .unknown
                let resolution = usesConservativeFlatParsing
                    ? StaticTargetResolution(targets: [], hasUnresolvedTargets: true)
                    : targetResolution(for: scopes, targetAnalysis: targetAnalysis)
                let exactTarget = !resolution.hasUnresolvedTargets && resolution.targets.count == 1
                    ? resolution.targets.first
                    : nil
                let declaration = usesConservativeFlatParsing
                    ? PodfileDeclaration(
                        line: offset + 1,
                        scope: .dynamicScope,
                        source: source
                    )
                    : declarationEvidence(
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
                    sourceProvenance: parsedSource.sourceProvenance,
                    isDirect: true,
                    targets: targetNames,
                    declarations: [declaration],
                    targetAttribution: attribution
                ))
            }

            if !usesConservativeFlatParsing && opensGenericBlock(trimmed) {
                scopes.append(.dynamic)
            }
        }

        if !scopes.isEmpty {
            features.hasDynamicRuby = true
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
                sourceProvenance: dependency.sourceProvenance,
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
        var activeTargetLines: [Int] = []
        var uncertainScopeDepth = 0
        var scopeDepth = 0
        var hasUnsupportedNesting = false

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if isEnd(trimmed) {
                if let removed = scopes.popLast() {
                    scopeDepth -= 1
                    switch removed {
                    case .target(let line):
                        if activeTargetLines.last == line {
                            activeTargetLines.removeLast()
                        }
                    case .dynamic, .opaque:
                        uncertainScopeDepth -= 1
                    case .abstractTarget:
                        break
                    }
                }
                continue
            }

            if trimmed.hasPrefix("def ") {
                let newDepth = scopeDepth + 1
                if newDepth > Self.maxStaticScopeNestingDepth {
                    hasUnsupportedNesting = true
                }
                scopes.append(.opaque)
                scopeDepth = newDepth
                uncertainScopeDepth += 1
                continue
            }

            if let name = targetName(from: trimmed, keyword: "target") {
                let parent = activeTargetLines.last
                let newDepth = scopeDepth + 1
                let isSupportedDepth = newDepth <= Self.maxStaticScopeNestingDepth
                if !isSupportedDepth {
                    hasUnsupportedNesting = true
                }
                nodes[offset] = TargetNode(
                    name: name,
                    parentLine: parent,
                    isProven: uncertainScopeDepth == 0 && isSupportedDepth,
                    uncertainScopeDepthAtDeclaration: uncertainScopeDepth
                )
                scopes.append(.target(offset))
                activeTargetLines.append(offset)
                scopeDepth = newDepth
                continue
            }

            if targetName(from: trimmed, keyword: "abstract_target") != nil {
                let newDepth = scopeDepth + 1
                if newDepth > Self.maxStaticScopeNestingDepth {
                    hasUnsupportedNesting = true
                }
                scopes.append(.abstractTarget)
                scopeDepth = newDepth
                continue
            }

            if trimmed.hasPrefix("inherit!") {
                guard let targetLine = activeTargetLines.last,
                      var node = nodes[targetLine] else {
                    continue
                }
                let hasUncertainScope = uncertainScopeDepth
                    > node.uncertainScopeDepthAtDeclaration
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

            if PodfileStaticSyntax.isTargetDeclaration(trimmed)
                || trimmed.hasPrefix("abstract_target ") {
                if let targetLine = activeTargetLines.last, var node = nodes[targetLine] {
                    node.hasUnknownDescendants = true
                    nodes[targetLine] = node
                }
            }

            if opensGenericBlock(trimmed) {
                let newDepth = scopeDepth + 1
                if newDepth > Self.maxStaticScopeNestingDepth {
                    hasUnsupportedNesting = true
                }
                scopes.append(.dynamic)
                scopeDepth = newDepth
                uncertainScopeDepth += 1
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

        var resolutions: [Int: StaticTargetResolution] = [:]
        for line in nodes.keys.sorted(by: >) {
            guard let node = nodes[line], node.isProven else {
                resolutions[line] = StaticTargetResolution(
                    targets: [],
                    hasUnresolvedTargets: true
                )
                continue
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
                    guard let childResolution = resolutions[childLine] else {
                        hasUnresolvedTargets = true
                        continue
                    }
                    targets.formUnion(childResolution.targets)
                    hasUnresolvedTargets = hasUnresolvedTargets
                        || childResolution.hasUnresolvedTargets
                case .excludes:
                    break
                case .unknown:
                    hasUnresolvedTargets = true
                }
            }

            resolutions[line] = StaticTargetResolution(
                targets: Array(targets).sorted(),
                hasUnresolvedTargets: hasUnresolvedTargets
            )
        }
        return TargetAnalysis(
            resolutionsByLine: resolutions,
            hasUnsupportedNesting: hasUnsupportedNesting
        )
    }

    /// Performs a deliberately small static analysis of Ruby helpers. It does
    /// not execute Ruby and does not follow helper-to-helper calls.
    private func analyzeHelpers(
        lines: [String],
        targetAnalysis: TargetAnalysis
    ) -> HelperAnalysis {
        guard !targetAnalysis.hasUnsupportedNesting else {
            return HelperAnalysis(
                resolutions: [:],
                eligibleDefinitionLines: [],
                dynamicLines: []
            )
        }

        var definitions: [HelperDefinition] = []
        var executableLines: [HelperExecutableLine] = []
        var scopes: [HelperScope] = []
        var activeHelperDefinitions: [Int] = []

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if isEnd(trimmed) {
                if let removed = scopes.popLast(), case .helper(let index) = removed,
                   activeHelperDefinitions.last == index {
                    activeHelperDefinitions.removeLast()
                }
                continue
            }

            if let target = targetName(from: trimmed, keyword: "target") {
                if let index = activeHelperDefinitions.last {
                    definitions[index].hasUnsupportedBody = true
                }
                scopes.append(.target(target, line: offset))
                continue
            }

            if let abstractTarget = targetName(from: trimmed, keyword: "abstract_target") {
                if let index = activeHelperDefinitions.last {
                    definitions[index].hasUnsupportedBody = true
                }
                scopes.append(.abstractTarget(abstractTarget))
                continue
            }

            if trimmed.hasPrefix("def ") {
                if let index = activeHelperDefinitions.last {
                    definitions[index].hasUnsupportedBody = true
                }
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
                activeHelperDefinitions.append(definitionIndex)
                continue
            }

            if isLiteralPodDeclaration(trimmed) {
                continue
            }

            if isStaticHelperDirective(trimmed) {
                continue
            }

            if let index = activeHelperDefinitions.last {
                definitions[index].hasUnsupportedBody = true
            }
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
                && !Self.modeledDSLHelperNames.contains(helperName)
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

    /// Returns true only for complete physical-line statements whose effect on
    /// declaration reachability is explicitly modeled by this parser. Unknown
    /// executable Ruby must fail closed: even a standalone `next`, `raise`, or
    /// arbitrary method call can prevent a later literal `pod` from running.
    private func isStaticallyModeledStatement(
        _ line: String,
        line offset: Int,
        helperAnalysis: HelperAnalysis
    ) -> Bool {
        // A dependency can still be reported and target-attributed when its
        // options are unsupported. It may prove later Ruby reachability only
        // when the whole declaration is exactly representable; unknown or
        // extra options can raise before subsequent pod calls execute.
        let isReachabilitySafePodDeclaration = isLiteralPodDeclaration(line)
            && isRepresentablePodDeclaration(line)
        if PodfileStaticSyntax.closesBlock(line)
            || PodfileStaticSyntax.targetName(from: line) != nil
            || PodfileStaticSyntax.abstractTargetName(from: line) != nil
            || isReachabilitySafePodDeclaration
            || helperAnalysis.eligibleDefinitionLines.contains(offset)
            || isStaticHelperDirective(line) {
            return true
        }

        let integrationDirectives = [
            "use_react_native!",
            "flutter_install_all_ios_pods",
            "capacitor_pods",
        ]
        if integrationDirectives.contains(where: {
            PodfileStaticSyntax.isDirectiveInvocation($0, in: line)
        }) {
            return true
        }

        if line.hasPrefix("post_install ") || line.hasPrefix("pre_install ") {
            return true
        }

        let staticMetadataPatterns = [
            #"^platform\s+:[A-Za-z_]\w*(?:\s*,\s*['"][A-Za-z0-9._-]+['"])?\s*(?:#.*)?$"#,
            #"^inherit!\s+:(?:search_paths|none|complete)\s*(?:#.*)?$"#,
        ]
        if staticMetadataPatterns.contains(where: {
            line.range(of: $0, options: .regularExpression) != nil
        }) {
            return true
        }

        guard let helperName = simpleHelperInvocationName(
            from: rubyCodeBeforeComment(line)
        ) else {
            return false
        }
        return helperAnalysis.resolutions[helperName] != nil
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

        return true
    }

    private func isRepresentablePodDeclaration(_ line: String) -> Bool {
        if PodfileStaticSyntax.representablePodName(from: line) != nil {
            return true
        }
        if case .supported = PodfileStaticSyntax.externalGitSource(from: line) {
            return true
        }
        return false
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

    private func parsedPodSource(from line: String) -> ParsedPodSource {
        switch PodfileStaticSyntax.externalGitSource(from: line) {
        case .supported(let rawURL, let rawRef):
            let repository = GitRepositoryCanonicalizer.evidence(for: rawURL)
            let reference = gitReferenceEvidence(from: rawRef)
            let safeReference = reference ?? .unpinned
            let provenance = GitSourceProvenance(declarations: [
                GitDeclarationEvidence(
                    repository: repository,
                    reference: safeReference,
                    syntaxIsSupported: reference != nil
                ),
            ])
            return ParsedPodSource(
                source: .git(
                    url: repository.displayURL,
                    ref: legacyGitRef(from: safeReference)
                ),
                sourceProvenance: .git(provenance)
            )
        case .unsupported:
            return ParsedPodSource(
                source: .unknown,
                sourceProvenance: .git(.unsupportedSyntax)
            )
        case .none:
            if let path = optionValue(named: "path", in: line) {
                return ParsedPodSource(source: .path(path))
            }
            return ParsedPodSource(source: .registry)
        }
    }

    private func gitReferenceEvidence(from ref: GitRef?) -> GitReferenceEvidence? {
        guard let ref else { return .unpinned }
        switch ref {
        case .branch(let value):
            return .make(kind: .branch, value: value)
        case .tag(let value):
            return .make(kind: .tag, value: value)
        case .commit(let value):
            return .make(kind: .commit, value: value)
        }
    }

    private func legacyGitRef(from evidence: GitReferenceEvidence) -> GitRef? {
        guard let value = evidence.value else { return nil }
        switch evidence.kind {
        case .branch:
            return .branch(value)
        case .tag:
            return .tag(value)
        case .commit:
            return .commit(value)
        case .unpinned:
            return nil
        }
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
        let code = rubyCodeBeforeComment(line)
        if code.range(
            of: #"\bdo(?:\s*\|.*\|)?\s*$"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        let prefixes = [
            "if ", "unless ", "case ", "for ", "while ", "until ",
            "class ", "module ", "begin",
        ]
        return prefixes.contains(where: { code.hasPrefix($0) })
    }

    /// Ruby comments and physical statements end at ASCII LF, optionally
    /// preceded by CR. Foundation's broad `.newlines` character set also
    /// splits Unicode separators that Ruby keeps inside the current line;
    /// doing so could turn commented text into synthetic executable lines.
    private func rubyPhysicalLines(in content: String) -> [String] {
        content.unicodeScalars.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map { scalars in
            let line = String(scalars)
            guard line.hasSuffix("\r") else { return line }
            return String(line.dropLast())
        }
    }

    private func containsHeredocOpener(_ line: String) -> Bool {
        rubyCodeOutsideStrings(rubyCodeBeforeComment(line)).contains("<<")
    }

    private func containsUnsupportedBraceSyntax(_ line: String) -> Bool {
        let code = rubyCodeOutsideStrings(rubyCodeBeforeComment(line))
        return code.contains("{") || code.contains("}")
    }

    private func sanitizedLinesForStaticAnalysis(_ lines: [String]) -> LexicalAnalysis {
        var sanitized: [String] = []
        sanitized.reserveCapacity(lines.count)
        var inBlockComment = false
        var reachedDataSection = false
        var hasUnsupportedStructure = false

        for line in lines {
            if reachedDataSection {
                sanitized.append("")
                continue
            }
            if inBlockComment {
                if isEmbeddedDocumentDirective(line, keyword: "end") {
                    inBlockComment = false
                }
                sanitized.append("")
                continue
            }
            if PodfileStaticSyntax.containsUnsupportedLexicalCharacter(line) {
                hasUnsupportedStructure = true
            }
            if isEmbeddedDocumentDirective(line, keyword: "begin") {
                inBlockComment = true
                sanitized.append("")
                continue
            }
            if isEmbeddedDocumentDirective(line, keyword: "end") {
                hasUnsupportedStructure = true
                sanitized.append("")
                continue
            }
            if line.range(
                of: #"^__END__(?:\s*#.*)?$"#,
                options: .regularExpression
            ) != nil {
                reachedDataSection = true
                sanitized.append("")
                continue
            }
            if hasUnsupportedCrossLineRubySyntax(line) {
                hasUnsupportedStructure = true
            }
            sanitized.append(line)
        }

        return LexicalAnalysis(
            lines: sanitized,
            hasUnsupportedStructure: hasUnsupportedStructure || inBlockComment
        )
    }

    /// PkgLift only proves declarations whose complete Ruby syntax is present
    /// on one physical line. Ruby's multiline literals and continuation rules
    /// can otherwise make a later `target` or `pod` line non-executable while
    /// still looking like an independent declaration to the static parser.
    private func hasUnsupportedCrossLineRubySyntax(_ line: String) -> Bool {
        let code = rubyCodeBeforeComment(line)
        guard !code.isEmpty else { return false }

        if hasUnterminatedQuotedLiteral(code) {
            return true
        }

        let codeOutsideStrings = rubyCodeOutsideStrings(code)
        if codeOutsideStrings.contains(";")
            || codeOutsideStrings.contains("%")
            || codeOutsideStrings.contains("/") {
            return true
        }

        var parenthesisDepth = 0
        var bracketDepth = 0
        for character in codeOutsideStrings {
            switch character {
            case "(":
                parenthesisDepth += 1
            case ")":
                parenthesisDepth -= 1
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth -= 1
            default:
                break
            }
            if parenthesisDepth < 0 || bracketDepth < 0 {
                return true
            }
        }
        if parenthesisDepth != 0 || bracketDepth != 0 {
            return true
        }

        return code.range(
            of: #"(?:\\|&&|\|\||\band\b|\bor\b|[+\-*\/%=&|^<>?:,.])\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private func hasUnterminatedQuotedLiteral(_ code: String) -> Bool {
        var quote: Character?
        var escaped = false

        for character in code {
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
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
            } else if character == "#" {
                break
            }
        }
        return quote != nil
    }

    private func isEmbeddedDocumentDirective(_ line: String, keyword: String) -> Bool {
        let directive = "=\(keyword)"
        guard line.hasPrefix(directive) else { return false }
        let suffix = line.dropFirst(directive.count)
        guard let first = suffix.first else { return true }
        return first == " " || first == "\t"
    }
}

private struct LexicalAnalysis {
    let lines: [String]
    let hasUnsupportedStructure: Bool
}

private struct ParsedPodSource {
    let source: PodSource
    let sourceProvenance: DependencySourceProvenance?

    init(
        source: PodSource,
        sourceProvenance: DependencySourceProvenance? = nil
    ) {
        self.source = source
        self.sourceProvenance = sourceProvenance
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
    let hasUnsupportedNesting: Bool
}

private struct StaticTargetResolution {
    let targets: [String]
    let hasUnresolvedTargets: Bool
}

private struct TargetNode {
    let name: String
    let parentLine: Int?
    let isProven: Bool
    let uncertainScopeDepthAtDeclaration: Int
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
