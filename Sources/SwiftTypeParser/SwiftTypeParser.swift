import Foundation
import SDGECore

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

public struct HeuristicSwiftTypeParser: SwiftTypeParsing {
    public init() {}

    public func parse(file: SwiftSourceFile, includeBodyReferences: Bool) throws -> [SwiftType] {
        let source = Self.maskingCommentsAndStringContents(from: file.contents)
        let characters = Array(source.utf16)
        let sourceString = source as NSString
        let fullRange = NSRange(location: 0, length: sourceString.length)

        var types: [SwiftType] = []
        var indicesByName: [String: Int] = [:]

        for match in Self.declarationExpression.matches(in: source, range: fullRange) {
            guard
                let kind = SwiftTypeKind(rawValue: sourceString.substring(with: match.range(at: 1))),
                let bodyRange = Self.bodyRange(afterOpeningDelimiterAt: NSMaxRange(match.range) - 1, in: characters)
            else {
                continue
            }

            let name = sourceString.substring(with: match.range(at: 2))
            let header = sourceString.substring(with: match.range(at: 3))
            let relationships = Self.relationships(in: header, kind: kind)
            let body = sourceString.substring(with: bodyRange)
            let members = Self.members(in: body, includeBodyReferences: includeBodyReferences)

            let type = SwiftType(
                name: name,
                kind: kind,
                filePath: file.path,
                inheritedTypes: relationships.inherited,
                conformances: relationships.conformances,
                members: members
            )

            indicesByName[name] = types.count
            types.append(type)
        }

        for match in Self.extensionExpression.matches(in: source, range: fullRange) {
            guard
                let index = indicesByName[sourceString.substring(with: match.range(at: 1))],
                let bodyRange = Self.bodyRange(afterOpeningDelimiterAt: NSMaxRange(match.range) - 1, in: characters)
            else {
                continue
            }

            let header = sourceString.substring(with: match.range(at: 2))
            let body = sourceString.substring(with: bodyRange)
            let relationships = Self.relationships(in: header, kind: nil)

            Self.appendUnique(relationships.conformances, to: &types[index].conformances)
            Self.appendUnique(
                Self.members(in: body, includeBodyReferences: includeBodyReferences),
                to: &types[index].members
            )
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
            let source = Self.maskingCommentsAndStringContents(from: file.contents)
            for contribution in Self.extensionContributions(
                in: source,
                includeBodyReferences: includeBodyReferences
            ) {
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

private extension HeuristicSwiftTypeParser {
    struct ExtensionContribution {
        let typeName: String
        let conformances: [String]
        let members: [SwiftMember]
    }

    static let declarationExpression = try! NSRegularExpression(
        pattern: #"\b(class|struct|enum|protocol|actor)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^{}>]*>)?\s*([^{}]*)\{"#
    )

    static let extensionExpression = try! NSRegularExpression(
        pattern: #"\bextension\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^{}>]*>)?\s*([^{}]*)\{"#
    )

    static let propertyExpression = try! NSRegularExpression(
        pattern: #"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^=\{\n]+)"#
    )

    static let initializerExpression = try! NSRegularExpression(
        pattern: #"\binit\s*(?:[?!])?\s*\("#
    )

    static let functionExpression = try! NSRegularExpression(
        pattern: #"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^{}()]*>)?\s*\("#
    )

    static let bodyReferenceExpression = try! NSRegularExpression(
        pattern: #"\b([A-Z][A-Za-z0-9_]*)\s*(?:<[^{}()]*>)?\s*\("#
    )

    static let identifierExpression = try! NSRegularExpression(
        pattern: #"[A-Za-z_][A-Za-z0-9_]*"#
    )

    static func extensionContributions(
        in source: String,
        includeBodyReferences: Bool
    ) -> [ExtensionContribution] {
        let characters = Array(source.utf16)
        let sourceString = source as NSString
        let fullRange = NSRange(location: 0, length: sourceString.length)

        return extensionExpression.matches(in: source, range: fullRange).compactMap { match in
            guard let bodyRange = bodyRange(
                afterOpeningDelimiterAt: NSMaxRange(match.range) - 1,
                in: characters
            ) else {
                return nil
            }

            let typeName = sourceString.substring(with: match.range(at: 1))
            let header = sourceString.substring(with: match.range(at: 2))
            let body = sourceString.substring(with: bodyRange)
            return ExtensionContribution(
                typeName: typeName,
                conformances: relationships(in: header, kind: nil).conformances,
                members: members(in: body, includeBodyReferences: includeBodyReferences)
            )
        }
    }

    static func maskingCommentsAndStringContents(from source: String) -> String {
        enum LexicalContext {
            case code
            case string(isMultiline: Bool)
            case interpolation(depth: Int)
        }

        var characters = Array(source)
        var index = 0
        var blockDepth = 0
        var contexts: [LexicalContext] = [.code]

        while index < characters.count {
            if blockDepth > 0 {
                if hasPrefix("/*", in: characters, at: index) {
                    characters[index] = " "
                    characters[index + 1] = " "
                    blockDepth += 1
                    index += 2
                } else if hasPrefix("*/", in: characters, at: index) {
                    characters[index] = " "
                    characters[index + 1] = " "
                    blockDepth -= 1
                    index += 2
                } else {
                    if characters[index] != "\n" {
                        characters[index] = " "
                    }
                    index += 1
                }
                continue
            }

            switch contexts.last ?? .code {
            case .string(let isMultiline):
                if characters[index] == "\\" {
                    characters[index] = " "
                    if index + 1 < characters.count, characters[index + 1] == "(" {
                        contexts.append(.interpolation(depth: 1))
                        index += 2
                    } else {
                        if index + 1 < characters.count, characters[index + 1] != "\n" {
                            characters[index + 1] = " "
                        }
                        index += 2
                    }
                } else if isMultiline, hasPrefix("\"\"\"", in: characters, at: index) {
                    characters[index] = " "
                    characters[index + 1] = " "
                    characters[index + 2] = " "
                    contexts.removeLast()
                    index += 3
                } else if !isMultiline, characters[index] == "\"" {
                    characters[index] = " "
                    contexts.removeLast()
                    index += 1
                } else {
                    if characters[index] != "\n" {
                        characters[index] = " "
                    }
                    index += 1
                }
                continue

            case .code, .interpolation:
                break
            }

            if hasPrefix("//", in: characters, at: index) {
                while index < characters.count, characters[index] != "\n" {
                    characters[index] = " "
                    index += 1
                }
            } else if hasPrefix("/*", in: characters, at: index) {
                characters[index] = " "
                characters[index + 1] = " "
                blockDepth = 1
                index += 2
            } else if hasPrefix("\"\"\"", in: characters, at: index) {
                characters[index] = " "
                characters[index + 1] = " "
                characters[index + 2] = " "
                contexts.append(.string(isMultiline: true))
                index += 3
            } else if characters[index] == "\"" {
                characters[index] = " "
                contexts.append(.string(isMultiline: false))
                index += 1
            } else if case .interpolation(let depth) = contexts.last, characters[index] == "(" {
                contexts[contexts.count - 1] = .interpolation(depth: depth + 1)
                index += 1
            } else if case .interpolation(let depth) = contexts.last, characters[index] == ")" {
                if depth == 1 {
                    contexts.removeLast()
                } else {
                    contexts[contexts.count - 1] = .interpolation(depth: depth - 1)
                }
                index += 1
            } else {
                index += 1
            }
        }

        return String(characters)
    }

    static func hasPrefix(_ prefix: String, in characters: [Character], at index: Int) -> Bool {
        let prefixCharacters = Array(prefix)
        guard index + prefixCharacters.count <= characters.count else {
            return false
        }

        return characters[index..<(index + prefixCharacters.count)].elementsEqual(prefixCharacters)
    }

    static func bodyRange(afterOpeningDelimiterAt openingIndex: Int, in characters: [UInt16]) -> NSRange? {
        guard openingIndex >= 0, openingIndex < characters.count, characters[openingIndex] == 123 else {
            return nil
        }

        var depth = 1
        var index = openingIndex + 1

        while index < characters.count {
            if characters[index] == 123 {
                depth += 1
            } else if characters[index] == 125 {
                depth -= 1
                if depth == 0 {
                    return NSRange(location: openingIndex + 1, length: index - openingIndex - 1)
                }
            }
            index += 1
        }

        return nil
    }

    static func relationships(in header: String, kind: SwiftTypeKind?) -> (inherited: [String], conformances: [String]) {
        guard let colonIndex = header.firstIndex(of: ":") else {
            return ([], [])
        }

        let candidateGroups = splitTopLevel(String(header[header.index(after: colonIndex)...]), on: ",")
            .map(typeNames)
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

    static func members(in body: String, includeBodyReferences: Bool) -> [SwiftMember] {
        let bodyString = body as NSString
        let fullRange = NSRange(location: 0, length: bodyString.length)
        let characters = Array(body.utf16)
        let depths = braceDepths(in: characters)
        var members: [SwiftMember] = []

        for match in propertyExpression.matches(in: body, range: fullRange) where isTopLevel(match.range.location, depths: depths) {
            let name = bodyString.substring(with: match.range(at: 1))
            for typeName in typeNames(bodyString.substring(with: match.range(at: 2))) {
                appendUnique(SwiftMember(name: name, typeName: typeName, kind: .property), to: &members)
            }
        }

        for match in initializerExpression.matches(in: body, range: fullRange) where isTopLevel(match.range.location, depths: depths) {
            let openingParenthesis = NSMaxRange(match.range) - 1
            guard let closingParenthesis = matchingParenthesis(afterOpeningAt: openingParenthesis, in: characters) else {
                continue
            }

            let parametersRange = NSRange(location: openingParenthesis + 1, length: closingParenthesis - openingParenthesis - 1)
            appendUnique(
                parameters(in: bodyString.substring(with: parametersRange), kind: .initializerParameter),
                to: &members
            )
        }

        for match in functionExpression.matches(in: body, range: fullRange) where isTopLevel(match.range.location, depths: depths) {
            let openingParenthesis = NSMaxRange(match.range) - 1
            guard let closingParenthesis = matchingParenthesis(afterOpeningAt: openingParenthesis, in: characters) else {
                continue
            }

            let parametersRange = NSRange(location: openingParenthesis + 1, length: closingParenthesis - openingParenthesis - 1)
            appendUnique(parameters(in: bodyString.substring(with: parametersRange), kind: .methodParameter), to: &members)

            let callable = callableParts(after: closingParenthesis, in: characters)
            if let returnTypeRange = callable.returnTypeRange {
                let name = bodyString.substring(with: match.range(at: 1))
                for typeName in typeNames(bodyString.substring(with: returnTypeRange)) {
                    appendUnique(SwiftMember(name: name, typeName: typeName, kind: .methodReturn), to: &members)
                }
            }

            if includeBodyReferences, let openingBrace = callable.bodyOpeningBrace {
                if let functionBodyRange = bodyRange(afterOpeningDelimiterAt: openingBrace, in: characters) {
                    appendUnique(bodyReferences(in: bodyString.substring(with: functionBodyRange)), to: &members)
                }
            }
        }

        return members
    }

    static func braceDepths(in characters: [UInt16]) -> [Int] {
        var depths = Array(repeating: 0, count: characters.count)
        var depth = 0

        for index in characters.indices {
            depths[index] = depth
            if characters[index] == 123 {
                depth += 1
            } else if characters[index] == 125 {
                depth = max(0, depth - 1)
            }
        }

        return depths
    }

    static func isTopLevel(_ location: Int, depths: [Int]) -> Bool {
        location >= 0 && location < depths.count && depths[location] == 0
    }

    static func matchingParenthesis(afterOpeningAt openingIndex: Int, in characters: [UInt16]) -> Int? {
        guard openingIndex >= 0, openingIndex < characters.count, characters[openingIndex] == 40 else {
            return nil
        }

        var depth = 1
        var index = openingIndex + 1

        while index < characters.count {
            if characters[index] == 40 {
                depth += 1
            } else if characters[index] == 41 {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index += 1
        }

        return nil
    }

    static func parameters(in source: String, kind: SwiftMemberKind) -> [SwiftMember] {
        splitTopLevel(source, on: ",").flatMap { parameter -> [SwiftMember] in
            guard let colonIndex = parameter.firstIndex(of: ":") else {
                return []
            }

            let labels = parameter[..<colonIndex]
                .split(whereSeparator: { $0.isWhitespace })
                .filter { $0 != "_" }
            guard let name = labels.last.map(String.init) else {
                return []
            }

            let typeSource = String(parameter[parameter.index(after: colonIndex)...])
            return typeNames(prefixBeforeTopLevelEquals(in: typeSource)).map {
                SwiftMember(name: name, typeName: $0, kind: kind)
            }
        }
    }

    static func callableParts(after closingParenthesis: Int, in characters: [UInt16]) -> (returnTypeRange: NSRange?, bodyOpeningBrace: Int?) {
        let start = closingParenthesis + 1
        var arrowIndex: Int?
        var cursor = start

        while cursor < characters.count {
            if characters[cursor] == 45, cursor + 1 < characters.count, characters[cursor + 1] == 62 {
                arrowIndex = cursor
                cursor += 2
                continue
            }

            if characters[cursor] == 123 {
                let returnTypeRange = arrowIndex.map {
                    NSRange(location: $0 + 2, length: cursor - $0 - 2)
                }
                return (returnTypeRange, cursor)
            }

            if characters[cursor] == 59 {
                let returnTypeRange = arrowIndex.map {
                    NSRange(location: $0 + 2, length: cursor - $0 - 2)
                }
                return (returnTypeRange, nil)
            }

            if characters[cursor] == 10 || characters[cursor] == 13 {
                var nextNonWhitespace = cursor + 1
                while nextNonWhitespace < characters.count,
                      characters[nextNonWhitespace] == 10 || characters[nextNonWhitespace] == 13 || characters[nextNonWhitespace] == 32 || characters[nextNonWhitespace] == 9 {
                    nextNonWhitespace += 1
                }

                if nextNonWhitespace < characters.count, characters[nextNonWhitespace] == 123 {
                    cursor = nextNonWhitespace
                    continue
                }

                let returnTypeRange = arrowIndex.map {
                    NSRange(location: $0 + 2, length: cursor - $0 - 2)
                }
                return (returnTypeRange, nil)
            }

            cursor += 1
        }

        let returnTypeRange = arrowIndex.map {
            NSRange(location: $0 + 2, length: characters.count - $0 - 2)
        }
        return (returnTypeRange, nil)
    }

    static func bodyReferences(in source: String) -> [SwiftMember] {
        let sourceString = source as NSString
        let fullRange = NSRange(location: 0, length: sourceString.length)

        return bodyReferenceExpression.matches(in: source, range: fullRange).map { match in
            let typeName = sourceString.substring(with: match.range(at: 1))
            return SwiftMember(name: typeName, typeName: typeName, kind: .bodyReference)
        }
    }

    static func typeNames(_ source: String) -> [String] {
        let attributeStrippedSource = removingTypeAttributes(from: source)
        let sourceString = attributeStrippedSource as NSString
        let matches = identifierExpression.matches(
            in: attributeStrippedSource,
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

    static func removingTypeAttributes(from source: String) -> String {
        var characters = Array(source)
        var index = 0

        while index < characters.count {
            guard characters[index] == "@" else {
                index += 1
                continue
            }

            characters[index] = " "
            index += 1

            while index < characters.count,
                  characters[index].isLetter || characters[index].isNumber || characters[index] == "_" || characters[index] == "." {
                characters[index] = " "
                index += 1
            }

            var payloadStart = index
            while payloadStart < characters.count, characters[payloadStart].isWhitespace {
                payloadStart += 1
            }

            guard payloadStart < characters.count, characters[payloadStart] == "(" else {
                continue
            }

            var depth = 0
            index = payloadStart
            while index < characters.count {
                if characters[index] == "(" {
                    depth += 1
                } else if characters[index] == ")" {
                    depth -= 1
                }
                characters[index] = " "
                index += 1

                if depth == 0 {
                    break
                }
            }
        }

        return String(characters)
    }

    static func prefixBeforeTopLevelEquals(in source: String) -> String {
        var depth = 0

        for (index, character) in source.enumerated() {
            switch character {
            case "(", "[", "<":
                depth += 1
            case ")", "]", ">":
                depth = max(0, depth - 1)
            case "=" where depth == 0:
                return String(source.prefix(index))
            default:
                break
            }
        }

        return source
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

    static func splitTopLevel(_ source: String, on separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0

        for character in source {
            switch character {
            case "(", "[", "<":
                depth += 1
            case ")", "]", ">":
                depth = max(0, depth - 1)
            case let value where value == separator && depth == 0:
                parts.append(current)
                current = ""
                continue
            default:
                break
            }
            current.append(character)
        }

        parts.append(current)
        return parts
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
