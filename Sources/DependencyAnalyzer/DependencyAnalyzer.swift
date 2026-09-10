import SDGECore

public struct DependencyAnalyzer {
    public init() {}

    public func analyze(rootTypeName: String, types: [SwiftType], options: AnalysisOptions) -> DependencyGraph {
        let typesByName = Dictionary(types.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        guard let rootType = typesByName[rootTypeName] else {
            return DependencyGraph()
        }

        var nodes: Set<DependencyNode> = [DependencyNode(name: rootType.name, kind: rootType.kind, isExternal: false)]
        var edges: Set<DependencyEdge> = []

        if options.direction == .uses || options.direction == .both {
            expandOutgoing(
                from: rootType,
                typesByName: typesByName,
                options: options,
                nodes: &nodes,
                edges: &edges
            )
        }

        if options.direction == .usedBy || options.direction == .both {
            expandIncoming(
                from: rootType,
                allTypes: types,
                typesByName: typesByName,
                options: options,
                nodes: &nodes,
                edges: &edges
            )
        }

        return DependencyGraph(
            nodes: nodes.sorted { $0.name < $1.name },
            edges: edges.sorted { $0.id < $1.id }
        )
    }

    private func expandOutgoing(
        from rootType: SwiftType,
        typesByName: [String: SwiftType],
        options: AnalysisOptions,
        nodes: inout Set<DependencyNode>,
        edges: inout Set<DependencyEdge>
    ) {
        var queue = [(type: rootType, depth: 0)]
        var expandedDepthByType = [rootType.name: 0]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard current.depth < max(0, options.depth) else { continue }

            for dependency in dependencies(of: current.type) {
                let targetType = typesByName[dependency.name]
                let relationship = resolvedRelationship(dependency.relationship, targetType: targetType)
                guard shouldInclude(name: dependency.name, targetType: targetType, relationship: relationship, options: options) else {
                    continue
                }

                let isExternal = targetType == nil
                nodes.insert(DependencyNode(name: dependency.name, kind: targetType?.kind, isExternal: isExternal))
                edges.insert(DependencyEdge(
                    source: current.type.name,
                    target: dependency.name,
                    relationship: relationship,
                    isExternal: isExternal,
                    memberName: dependency.memberName
                ))

                if let targetType, let knownDepth = expandedDepthByType[targetType.name], knownDepth <= current.depth + 1 {
                    continue
                } else if let targetType {
                    let targetDepth = current.depth + 1
                    expandedDepthByType[targetType.name] = targetDepth
                    queue.append((targetType, targetDepth))
                }
            }
        }
    }

    private func expandIncoming(
        from rootType: SwiftType,
        allTypes: [SwiftType],
        typesByName: [String: SwiftType],
        options: AnalysisOptions,
        nodes: inout Set<DependencyNode>,
        edges: inout Set<DependencyEdge>
    ) {
        var queue = [(type: rootType, depth: 0)]
        var expandedDepthByType = [rootType.name: 0]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard current.depth < max(0, options.depth) else { continue }

            for candidate in allTypes {
                for dependency in dependencies(of: candidate) where dependency.name == current.type.name {
                    let relationship = resolvedRelationship(dependency.relationship, targetType: typesByName[current.type.name])
                    guard shouldInclude(name: candidate.name, targetType: candidate, relationship: relationship, options: options) else {
                        continue
                    }

                    nodes.insert(DependencyNode(name: candidate.name, kind: candidate.kind, isExternal: false))
                    edges.insert(DependencyEdge(
                        source: candidate.name,
                        target: current.type.name,
                        relationship: relationship,
                        isExternal: false,
                        memberName: dependency.memberName
                    ))

                    if let knownDepth = expandedDepthByType[candidate.name], knownDepth <= current.depth + 1 {
                        continue
                    }

                    let targetDepth = current.depth + 1
                    expandedDepthByType[candidate.name] = targetDepth
                    queue.append((candidate, targetDepth))
                }
            }
        }
    }

    private func dependencies(of type: SwiftType) -> [(name: String, relationship: DependencyRelationship, memberName: String?)] {
        let inherited: [(name: String, relationship: DependencyRelationship, memberName: String?)] = type.inheritedTypes.map {
            (name: $0, relationship: DependencyRelationship.inherits, memberName: nil)
        }
        let conformances: [(name: String, relationship: DependencyRelationship, memberName: String?)] = type.conformances.map {
            (name: $0, relationship: DependencyRelationship.conforms, memberName: nil)
        }
        let members: [(name: String, relationship: DependencyRelationship, memberName: String?)] = type.members.compactMap { member in
            relationship(for: member.kind).map { relationship in
                let memberName = member.kind == .bodyReference ? nil : member.name
                return (name: member.typeName, relationship: relationship, memberName: memberName)
            }
        }

        return inherited + conformances + members
    }

    private func resolvedRelationship(
        _ relationship: DependencyRelationship,
        targetType: SwiftType?
    ) -> DependencyRelationship {
        guard relationship == .inherits || relationship == .conforms else {
            return relationship
        }

        switch targetType?.kind {
        case .class:
            return .inherits
        case .protocol:
            return .conforms
        default:
            return relationship
        }
    }

    private func relationship(for kind: SwiftMemberKind) -> DependencyRelationship? {
        switch kind {
        case .property:
            return .property
        case .initializerParameter:
            return .initializerParameter
        case .methodParameter:
            return .methodParameter
        case .methodReturn:
            return .methodReturn
        case .bodyReference:
            return .bodyReference
        case .inheritance:
            return .inherits
        case .conformance:
            return .conforms
        }
    }

    private func shouldInclude(
        name: String,
        targetType: SwiftType?,
        relationship: DependencyRelationship,
        options: AnalysisOptions
    ) -> Bool {
        guard !name.isEmpty,
              !options.excludedPrefixes.contains(where: { name.hasPrefix($0) }) else {
            return false
        }

        guard relationship != .bodyReference || options.includeBodyReferences else {
            return false
        }

        if let targetType {
            return includes(kind: targetType.kind, options: options)
        }

        return isSystemType(name) ? options.includeSystemTypes : options.includeThirdPartyTypes
    }

    private func includes(kind: SwiftTypeKind, options: AnalysisOptions) -> Bool {
        switch kind {
        case .class:
            return options.includeClasses
        case .struct:
            return options.includeStructs
        case .enum:
            return options.includeEnums
        case .protocol:
            return options.includeProtocols
        case .actor:
            return true
        }
    }

    private func isSystemType(_ name: String) -> Bool {
        let systemNames: Set<String> = [
            "Any", "AnyObject", "Bool", "Character", "Data", "Date", "Decimal", "Dictionary", "Double",
            "Error", "Float", "Int", "Int8", "Int16", "Int32", "Int64", "NSArray", "NSDictionary",
            "NSNumber", "NSObject", "Optional", "Set", "String", "UInt", "UInt8", "UInt16", "UInt32",
            "UInt64", "URL", "UUID", "Void", "SwiftUI", "Combine", "Foundation", "UIKit", "AppKit",
            // Standard library / framework base protocols
            "Equatable", "Hashable", "Comparable", "Identifiable", "Sendable",
            "Codable", "Decodable", "Encodable", "RawRepresentable",
            "CustomStringConvertible", "CustomDebugStringConvertible", "LosslessStringConvertible",
            "CaseIterable", "OptionSet",
            "Sequence", "Collection", "BidirectionalCollection", "RandomAccessCollection",
            "MutableCollection", "RangeReplaceableCollection", "IteratorProtocol",
            "ExpressibleByNilLiteral", "ExpressibleByBooleanLiteral", "ExpressibleByIntegerLiteral",
            "ExpressibleByFloatLiteral", "ExpressibleByStringLiteral", "ExpressibleByUnicodeScalarLiteral",
            "ExpressibleByExtendedGraphemeClusterLiteral", "ExpressibleByArrayLiteral", "ExpressibleByDictionaryLiteral",
            "ObservableObject", "View", "Numeric", "SignedNumeric", "BinaryInteger",
            "FloatingPoint", "Strideable", "AdditiveArithmetic"
        ]
        let systemPrefixes = [
            "AV", "CA", "CB", "CF", "CG", "CI", "CL", "CN", "CK", "Core", "Dispatch", "HK",
            "MK", "MTK", "MTL", "NS", "OS", "PH", "SCN", "SK", "UI", "UN", "UT", "VN", "WK"
        ]

        return systemNames.contains(name) || systemPrefixes.contains(where: { name.hasPrefix($0) })
    }

}
