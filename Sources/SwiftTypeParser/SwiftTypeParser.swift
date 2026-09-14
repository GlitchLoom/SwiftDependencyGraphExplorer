import Foundation
import SDGECore
import SwiftParser
import SwiftSyntax

public protocol SwiftTypeParsing {
    func parse(file: SwiftSourceFile, includeBodyReferences: Bool) throws -> [SwiftType]
    func reconcileProject(
        types: [SwiftType],
        files: [SwiftSourceFile],
        includeBodyReferences: Bool
    ) throws -> [SwiftType]
}

public extension SwiftTypeParsing {
    func reconcileProject(
        types: [SwiftType],
        files: [SwiftSourceFile],
        includeBodyReferences: Bool
    ) throws -> [SwiftType] {
        types
    }
}

/// Parses Swift source with SwiftSyntax (the same parser the Swift compiler itself uses) rather
/// than regular expressions. This makes declaration/scope/member boundaries exact -- comments,
/// string literals, multi-line signatures, and nested braces no longer need special-case
/// handling -- while type-name extraction from a given type annotation still reuses the same
/// lightweight, already-proven text scan, since flattening generics/tuples/optionals/etc. to
/// their referenced names was never the fragile part.
public struct SwiftSyntaxTypeParser: SwiftTypeParsing {
    public init() {}

    public func parse(file: SwiftSourceFile, includeBodyReferences: Bool) throws -> [SwiftType] {
        let collector = Self.collect(from: file.contents, filePath: file.path, includeBodyReferences: includeBodyReferences)

        var types = collector.types
        for index in types.indices {
            types[index].imports = collector.imports
        }

        var indicesByName: [String: Int] = [:]
        for (index, type) in types.enumerated() {
            indicesByName[type.name] = index
        }

        for contribution in collector.extensionContributions {
            guard let index = indicesByName[contribution.typeName] else { continue }
            Self.appendUnique(contribution.conformances, to: &types[index].conformances)
            Self.appendUnique(contribution.members, to: &types[index].members)
        }

        return types
    }

    public func reconcileProject(
        types: [SwiftType],
        files: [SwiftSourceFile],
        includeBodyReferences: Bool
    ) throws -> [SwiftType] {
        var reconciledTypes = types
        let indicesByName = Dictionary(grouping: reconciledTypes.indices) { reconciledTypes[$0].name }

        for file in files {
            let collector = Self.collect(from: file.contents, filePath: file.path, includeBodyReferences: includeBodyReferences)

            for contribution in collector.extensionContributions {
                guard let candidates = indicesByName[contribution.typeName] else { continue }
                let sameFileIndex = candidates.first { reconciledTypes[$0].filePath == file.path }
                guard let index = sameFileIndex ?? (candidates.count == 1 ? candidates[0] : nil) else {
                    continue
                }

                Self.appendUnique(contribution.conformances, to: &reconciledTypes[index].conformances)
                Self.appendUnique(contribution.members, to: &reconciledTypes[index].members)
            }
        }

        return reconciledTypes
    }
}

private extension SwiftSyntaxTypeParser {
    struct ExtensionContribution {
        let typeName: String
        let conformances: [String]
        let members: [SwiftMember]
    }

    struct CollectorResult {
        let types: [SwiftType]
        let extensionContributions: [ExtensionContribution]
        let imports: [String]
    }

    static func collect(from source: String, filePath: String, includeBodyReferences: Bool) -> CollectorResult {
        let tree = Parser.parse(source: source)
        let visitor = TypeCollectingVisitor(filePath: filePath, includeBodyReferences: includeBodyReferences)
        visitor.walk(tree)
        return CollectorResult(types: visitor.types, extensionContributions: visitor.extensionContributions, imports: visitor.imports)
    }

    final class TypeCollectingVisitor: SyntaxVisitor {
        private(set) var types: [SwiftType] = []
        private(set) var extensionContributions: [ExtensionContribution] = []
        private(set) var imports: [String] = []

        private let filePath: String
        private let includeBodyReferences: Bool

        init(filePath: String, includeBodyReferences: Bool) {
            self.filePath = filePath
            self.includeBodyReferences = includeBodyReferences
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
            let moduleName = node.path.map { $0.name.text }.joined(separator: ".")
            SwiftSyntaxTypeParser.appendUnique(moduleName, to: &imports)
            return .skipChildren
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            collectType(name: node.name.text, kind: .class, inheritanceClause: node.inheritanceClause, memberBlock: node.memberBlock)
            return .visitChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            collectType(name: node.name.text, kind: .struct, inheritanceClause: node.inheritanceClause, memberBlock: node.memberBlock)
            return .visitChildren
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            collectType(name: node.name.text, kind: .enum, inheritanceClause: node.inheritanceClause, memberBlock: node.memberBlock)
            return .visitChildren
        }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            collectType(name: node.name.text, kind: .protocol, inheritanceClause: node.inheritanceClause, memberBlock: node.memberBlock)
            return .visitChildren
        }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            collectType(name: node.name.text, kind: .actor, inheritanceClause: node.inheritanceClause, memberBlock: node.memberBlock)
            return .visitChildren
        }

        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            guard let typeName = simpleName(of: node.extendedType) else { return .visitChildren }

            let relationships = SwiftSyntaxTypeParser.relationships(in: node.inheritanceClause, kind: nil)
            let members = SwiftSyntaxTypeParser.members(in: node.memberBlock, includeBodyReferences: includeBodyReferences)
            extensionContributions.append(ExtensionContribution(
                typeName: typeName,
                conformances: relationships.conformances,
                members: members
            ))
            return .visitChildren
        }

        private func collectType(
            name: String,
            kind: SwiftTypeKind,
            inheritanceClause: InheritanceClauseSyntax?,
            memberBlock: MemberBlockSyntax
        ) {
            let relationships = SwiftSyntaxTypeParser.relationships(in: inheritanceClause, kind: kind)
            let members = SwiftSyntaxTypeParser.members(in: memberBlock, includeBodyReferences: includeBodyReferences)
            types.append(SwiftType(
                name: name,
                kind: kind,
                filePath: filePath,
                inheritedTypes: relationships.inherited,
                conformances: relationships.conformances,
                members: members
            ))
        }

        /// The simple name an `extension` targets: the base type name for a plain or generic
        /// type, or the last component for a dotted type (matching how `typeNames` elsewhere
        /// only keeps the final component of a qualified name).
        private func simpleName(of type: TypeSyntax) -> String? {
            if let identifier = type.as(IdentifierTypeSyntax.self) {
                return identifier.name.text
            }
            if let member = type.as(MemberTypeSyntax.self) {
                return member.name.text
            }
            return nil
        }
    }

    // MARK: - Member extraction

    static func members(in memberBlock: MemberBlockSyntax, includeBodyReferences: Bool) -> [SwiftMember] {
        var members: [SwiftMember] = []

        for item in memberBlock.members {
            switch item.decl.kind {
            case .variableDecl:
                appendUnique(
                    propertyMembers(in: item.decl.cast(VariableDeclSyntax.self), includeBodyReferences: includeBodyReferences),
                    to: &members
                )
            case .initializerDecl:
                let node = item.decl.cast(InitializerDeclSyntax.self)
                appendUnique(parameterMembers(in: node.signature, kind: .initializerParameter), to: &members)
            case .functionDecl:
                let node = item.decl.cast(FunctionDeclSyntax.self)
                appendUnique(parameterMembers(in: node.signature, kind: .methodParameter), to: &members)
                appendUnique(returnMembers(of: node), to: &members)
                if includeBodyReferences, let body = node.body {
                    appendUnique(bodyReferences(in: body), to: &members)
                }
            default:
                break
            }
        }

        return members
    }

    static func propertyMembers(in node: VariableDeclSyntax, includeBodyReferences: Bool) -> [SwiftMember] {
        node.bindings.flatMap { binding -> [SwiftMember] in
            var members: [SwiftMember] = []

            if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
               let type = binding.typeAnnotation?.type {
                members += typeNames(from: type).map { SwiftMember(name: name, typeName: $0, kind: .property) }
            }

            // A property/static-let initializer (e.g. `static let live = AppServices(analyze: {
            // DependencyAnalyzer() }, ...)`) is itself an expression, not a `func` body, so it
            // needs its own scan for the same capitalized-call-expression references -- this is
            // how factory/DI-style closures assigned to a property get picked up.
            if includeBodyReferences, let initializerValue = binding.initializer?.value {
                members += bodyReferences(in: initializerValue)
            }

            return members
        }
    }

    static func parameterMembers(in signature: FunctionSignatureSyntax, kind: SwiftMemberKind) -> [SwiftMember] {
        signature.parameterClause.parameters.flatMap { parameter -> [SwiftMember] in
            let name = (parameter.secondName ?? parameter.firstName).text
            guard name != "_" else { return [] }
            return typeNames(from: parameter.type).map { SwiftMember(name: name, typeName: $0, kind: kind) }
        }
    }

    static func returnMembers(of node: FunctionDeclSyntax) -> [SwiftMember] {
        guard let returnType = node.signature.returnClause?.type else { return [] }
        let name = node.name.text
        return typeNames(from: returnType).map { SwiftMember(name: name, typeName: $0, kind: .methodReturn) }
    }

    static func bodyReferences(in node: some SyntaxProtocol) -> [SwiftMember] {
        let collector = BodyReferenceCollector()
        collector.walk(node)
        return collector.members
    }

    final class BodyReferenceCollector: SyntaxVisitor {
        private(set) var members: [SwiftMember] = []

        init() {
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let name = calleeName(of: node.calledExpression), name.first?.isUppercase == true {
                SwiftSyntaxTypeParser.appendUnique(SwiftMember(name: name, typeName: name, kind: .bodyReference), to: &members)
            }
            return .visitChildren
        }

        private func calleeName(of expression: ExprSyntax) -> String? {
            if let reference = expression.as(DeclReferenceExprSyntax.self) {
                return reference.baseName.text
            }
            if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
                return memberAccess.declName.baseName.text
            }
            return nil
        }
    }

    // MARK: - Inheritance / conformance classification

    static func relationships(
        in inheritanceClause: InheritanceClauseSyntax?,
        kind: SwiftTypeKind?
    ) -> (inherited: [String], conformances: [String]) {
        guard let inheritanceClause else { return ([], []) }

        let candidateGroups = inheritanceClause.inheritedTypes.map { typeNames(from: $0.type) }
        let candidates = candidateGroups.flatMap { $0 }

        if kind == .class, let firstGroup = candidateGroups.first, let firstCandidate = firstGroup.first {
            if isKnownProtocolConformance(firstCandidate) ||
                (candidateGroups.count == 1 && !hasStrongSuperclassSignal(firstCandidate)) {
                return ([], candidates)
            }
            return (firstGroup, candidateGroups.dropFirst().flatMap { $0 })
        }

        return ([], candidates)
    }

    // MARK: - Type-name flattening

    /// Extracts every referenced type name from a type annotation, flattening generic
    /// arguments, tuples, optionals, arrays/dictionaries, and function types down to their
    /// component names (e.g. `Repository<User>` -> `["Repository", "User"]`), the same way a
    /// dependency edge is derived elsewhere from a raw type string. Any top-level attribute
    /// (`@convention(c) () -> Void`) is stripped structurally first so its payload never leaks
    /// in as a fake identifier.
    static func typeNames(from type: TypeSyntax) -> [String] {
        var unwrapped = type
        while let attributed = unwrapped.as(AttributedTypeSyntax.self) {
            unwrapped = attributed.baseType
        }
        return typeNames(unwrapped.trimmedDescription)
    }

    static func typeNames(_ source: String) -> [String] {
        let sourceString = source as NSString
        let matches = identifierExpression.matches(
            in: source,
            range: NSRange(location: 0, length: sourceString.length)
        )

        let ignoredIdentifiers: Set<String> = ["any", "some", "inout", "async", "throws", "rethrows", "where", "self"]
        var names: [String] = []

        for match in matches {
            let name = sourceString.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            let preceding = previousNonWhitespaceCharacter(before: match.range.location, in: sourceString)
            let following = nextNonWhitespaceCharacter(after: NSMaxRange(match.range), in: sourceString)

            guard
                !name.isEmpty,
                !ignoredIdentifiers.contains(name),
                preceding != "@",
                following != "."
            else {
                continue
            }

            appendUnique(name, to: &names)
        }

        return names
    }

    static let identifierExpression = try! NSRegularExpression(
        pattern: #"[A-Za-z_][A-Za-z0-9_]*"#
    )

    static func isKnownProtocolConformance(_ name: String) -> Bool {
        let knownProtocolNames: Set<String> = ["Codable", "Decodable", "Encodable", "Identifiable", "ObservableObject"]

        return knownProtocolNames.contains(name) ||
            name.hasSuffix("Protocol") ||
            name.hasSuffix("Delegate") ||
            name.hasSuffix("DataSource")
    }

    static func hasStrongSuperclassSignal(_ name: String) -> Bool {
        let knownSuperclassNames: Set<String> = ["NSObject", "NSView", "NSViewController", "UIView", "UIViewController"]

        return knownSuperclassNames.contains(name) ||
            name.hasSuffix("ViewController") ||
            name.hasSuffix("View") ||
            name.hasSuffix("Controller") ||
            name.hasSuffix("Object") ||
            name.hasSuffix("Operation")
    }

    static func previousNonWhitespaceCharacter(before index: Int, in source: NSString) -> Character? {
        var cursor = index - 1
        while cursor >= 0 {
            let character = Character(UnicodeScalar(source.character(at: cursor))!)
            if !character.isWhitespace {
                return character
            }
            cursor -= 1
        }
        return nil
    }

    static func nextNonWhitespaceCharacter(after index: Int, in source: NSString) -> Character? {
        var cursor = index
        while cursor < source.length {
            let character = Character(UnicodeScalar(source.character(at: cursor))!)
            if !character.isWhitespace {
                return character
            }
            cursor += 1
        }
        return nil
    }

    static func appendUnique<T: Equatable>(_ values: [T], to destination: inout [T]) {
        for value in values where !destination.contains(value) {
            destination.append(value)
        }
    }

    static func appendUnique<T: Equatable>(_ value: T, to destination: inout [T]) {
        appendUnique([value], to: &destination)
    }
}
