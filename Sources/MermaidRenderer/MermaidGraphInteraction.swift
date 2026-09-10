import SDGECore

public struct MermaidGraphInteraction: Codable, Equatable {
    public struct Node: Codable, Equatable {
        public let name: String
        public let mermaidID: String
        public let isExternal: Bool
    }

    public struct Edge: Codable, Equatable {
        public let sourceName: String
        public let targetName: String
        public let sourceMermaidID: String
        public let targetMermaidID: String
        public let relationship: String
        public let memberName: String?
    }

    public let rootNodeName: String?
    public let nodes: [Node]
    public let edges: [Edge]

    public init(
        graph: DependencyGraph,
        rootNodeName: String?,
        nodeIdentifiers: [String: String]
    ) {
        self.rootNodeName = rootNodeName
        self.nodes = graph.nodes
            .sorted { $0.name < $1.name }
            .compactMap { node in
                guard let mermaidID = nodeIdentifiers[node.name] else { return nil }
                return Node(
                    name: node.name,
                    mermaidID: mermaidID,
                    isExternal: node.isExternal
                )
            }
        self.edges = graph.edges
            .sorted { ($0.source, $0.target, $0.relationship.rawValue) < ($1.source, $1.target, $1.relationship.rawValue) }
            .compactMap { edge in
                guard let sourceMermaidID = nodeIdentifiers[edge.source],
                      let targetMermaidID = nodeIdentifiers[edge.target] else {
                    return nil
                }
                return Edge(
                    sourceName: edge.source,
                    targetName: edge.target,
                    sourceMermaidID: sourceMermaidID,
                    targetMermaidID: targetMermaidID,
                    relationship: edge.relationship.rawValue,
                    memberName: edge.memberName
                )
            }
    }
}
