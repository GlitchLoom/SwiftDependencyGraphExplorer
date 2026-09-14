import Foundation

public struct SwiftSourceFile: Equatable, Identifiable {
    public var id: String { path }
    public let url: URL
    public let path: String
    public let contents: String

    public init(url: URL, path: String, contents: String) {
        self.url = url
        self.path = path
        self.contents = contents
    }
}

public enum SwiftTypeKind: String, CaseIterable, Codable, Equatable {
    case `class`, `struct`, `enum`, `protocol`, actor
}

public enum SwiftMemberKind: String, Codable, Equatable {
    case property
    case initializerParameter
    case methodParameter
    case methodReturn
    case bodyReference
    case inheritance
    case conformance
}

public struct SwiftMember: Codable, Equatable, Hashable {
    public let name: String
    public let typeName: String
    public let kind: SwiftMemberKind

    public init(name: String, typeName: String, kind: SwiftMemberKind) {
        self.name = name
        self.typeName = typeName
        self.kind = kind
    }
}

public struct SwiftType: Identifiable, Codable, Equatable {
    public var id: String { "\(filePath)::\(name)" }
    public let name: String
    public let kind: SwiftTypeKind
    public let filePath: String
    public var inheritedTypes: [String]
    public var conformances: [String]
    public var members: [SwiftMember]
    /// The modules named in `import` declarations of the file this type was declared in.
    public var imports: [String]

    public init(name: String, kind: SwiftTypeKind, filePath: String, inheritedTypes: [String] = [], conformances: [String] = [], members: [SwiftMember] = [], imports: [String] = []) {
        self.name = name
        self.kind = kind
        self.filePath = filePath
        self.inheritedTypes = inheritedTypes
        self.conformances = conformances
        self.members = members
        self.imports = imports
    }
}

public enum DependencyRelationship: String, Codable, Equatable {
    case inherits = "inherits"
    case conforms = "conforms"
    case property = "property"
    case initializerParameter = "init parameter"
    case methodParameter = "method parameter"
    case methodReturn = "returns"
    case bodyReference = "body reference"
}

public struct DependencyNode: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let kind: SwiftTypeKind?
    public let isExternal: Bool

    public init(name: String, kind: SwiftTypeKind?, isExternal: Bool) {
        self.id = name
        self.name = name
        self.kind = kind
        self.isExternal = isExternal
    }
}

public struct DependencyEdge: Identifiable, Codable, Equatable, Hashable {
    public var id: String { "\(source)->\(target):\(relationship.rawValue):\(memberName ?? "")" }
    public let source: String
    public let target: String
    public let relationship: DependencyRelationship
    public let isExternal: Bool
    /// The property, parameter, or function name that introduces this dependency (e.g. "viewModel" for a
    /// property, or the function name for a return type). Nil for inheritance/conformance edges, which
    /// have no associated member.
    public let memberName: String?

    public init(source: String, target: String, relationship: DependencyRelationship, isExternal: Bool, memberName: String? = nil) {
        self.source = source
        self.target = target
        self.relationship = relationship
        self.isExternal = isExternal
        self.memberName = memberName
    }
}

public struct DependencyGraph: Codable, Equatable {
    public var nodes: [DependencyNode]
    public var edges: [DependencyEdge]

    public init(nodes: [DependencyNode] = [], edges: [DependencyEdge] = []) {
        self.nodes = nodes
        self.edges = edges
    }
}

public enum AnalysisDirection: String, CaseIterable, Codable, Equatable {
    case uses
    case usedBy
    case both

    public var label: String {
        switch self {
        case .uses:
            return "Uses"
        case .usedBy:
            return "Used By"
        case .both:
            return "Both"
        }
    }
}

public struct AnalysisOptions: Codable, Equatable {
    public var depth: Int
    public var direction: AnalysisDirection
    public var includeSystemTypes: Bool
    public var includeThirdPartyTypes: Bool
    public var includeBodyReferences: Bool
    public var includeProtocols: Bool
    public var includeClasses: Bool
    public var includeStructs: Bool
    public var includeEnums: Bool
    public var excludedPrefixes: [String]

    public static let defaults = AnalysisOptions(
        depth: 2,
        direction: .uses,
        includeSystemTypes: false,
        includeThirdPartyTypes: true,
        includeBodyReferences: false,
        includeProtocols: true,
        includeClasses: true,
        includeStructs: true,
        includeEnums: true,
        excludedPrefixes: []
    )
}
