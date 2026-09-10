import SDGECore

public struct MermaidGraphBuilder {
    public init() {}

    public func buildMermaid(from graph: DependencyGraph) -> String {
        let nodes = graph.nodes.sorted { $0.name < $1.name }
        let identifiers = identifiers(for: nodes)
        var lines = ["flowchart LR"]

        lines += nodes.map { node in
            "    \(identifiers[node.name, default: sanitizeIdentifier(node.name)])[\"\(escapeMermaidLabel(node.name))\"]"
        }

        let edges = graph.edges.sorted(by: edgeComesBefore)
        var seenPairs: Set<String> = []
        let uniquePairEdges = edges.filter { seenPairs.insert("\($0.source)->\($0.target)").inserted }
        lines += uniquePairEdges.map { edge in
            let source = identifiers[edge.source, default: sanitizeIdentifier(edge.source)]
            let target = identifiers[edge.target, default: sanitizeIdentifier(edge.target)]
            return "    \(source) --> \(target)"
        }

        let externalIdentifiers = nodes
            .filter(\.isExternal)
            .compactMap { identifiers[$0.name] }
            .sorted()
        lines += externalIdentifiers.map { "    class \($0) external" }
        lines.append("    classDef external stroke-dasharray: 5 5")

        return lines.joined(separator: "\n")
    }

    public func nodeIdentifiers(for graph: DependencyGraph) -> [String: String] {
        identifiers(for: graph.nodes.sorted { $0.name < $1.name })
    }

    public func buildDOT(from graph: DependencyGraph) -> String {
        let nodes = graph.nodes.sorted { $0.name < $1.name }
        var lines = ["digraph DependencyGraph {"]

        lines += nodes.map { node in
            let style = node.isExternal ? ", style=dashed" : ""
            return "    \"\(escapeDOT(node.name))\" [label=\"\(escapeDOT(node.name))\"\(style)];"
        }

        lines += graph.edges.sorted(by: edgeComesBefore).map { edge in
            "    \"\(escapeDOT(edge.source))\" -> \"\(escapeDOT(edge.target))\" [label=\"\(escapeDOT(edge.relationship.rawValue))\"];"
        }
        lines.append("}")

        return lines.joined(separator: "\n")
    }

    private func identifiers(for nodes: [DependencyNode]) -> [String: String] {
        var identifiers: [String: String] = [:]
        var used: Set<String> = []

        for node in nodes {
            let base = sanitizeIdentifier(node.name)
            var identifier = base
            var suffix = 2
            while used.contains(identifier) {
                identifier = "\(base)_\(suffix)"
                suffix += 1
            }
            identifiers[node.name] = identifier
            used.insert(identifier)
        }

        return identifiers
    }

    private func sanitizeIdentifier(_ name: String) -> String {
        let sanitized = name.unicodeScalars.map { scalar in
            scalar.value == 95 || (scalar.value >= 48 && scalar.value <= 57) ||
                (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
                ? Character(String(scalar))
                : "_"
        }
        let result = String(sanitized)
        return result.isEmpty ? "_" : result
    }

    private func escapeMermaidLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func escapeDOT(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func edgeComesBefore(_ lhs: DependencyEdge, _ rhs: DependencyEdge) -> Bool {
        (lhs.source, lhs.target, lhs.relationship.rawValue) < (rhs.source, rhs.target, rhs.relationship.rawValue)
    }
}
