import ArgumentParser
import Foundation
import GraphBuilder
import SDGECore

enum DirectionOption: String, ExpressibleByArgument, CaseIterable {
    case uses
    case usedBy = "used-by"
    case both

    var analysisDirection: AnalysisDirection {
        switch self {
        case .uses: return .uses
        case .usedBy: return .usedBy
        case .both: return .both
        }
    }
}

enum GraphFormat: String, ExpressibleByArgument, CaseIterable {
    case mermaid
    case dot
    case json

    func render(_ graph: DependencyGraph) throws -> String {
        switch self {
        case .mermaid:
            return MermaidGraphBuilder().buildMermaid(from: graph)
        case .dot:
            return MermaidGraphBuilder().buildDOT(from: graph)
        case .json:
            return try Self.prettyJSON(graph)
        }
    }

    static func prettyJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

enum ListFormat: String, ExpressibleByArgument, CaseIterable {
    case text
    case json
}

/// Writes to the given file path, or stdout when none is given.
func emit(_ content: String, to outputPath: String?) throws {
    guard let outputPath else {
        print(content)
        return
    }
    try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
}

func parseExcludedPrefixes(_ raw: String) -> [String] {
    raw.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}
