import ArgumentParser
import Foundation
import SDGECore

struct ListTypes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-types",
        abstract: "List the Swift types discovered in a project, as candidates for `analyze --root-type`."
    )

    @Option(name: .shortAndLong, help: "Path to the Swift project's root folder.")
    var path: String = FileManager.default.currentDirectoryPath

    @Option(help: "Output format: text or json.")
    var format: ListFormat = .text

    @Option(name: .shortAndLong, help: "Write output to this file instead of stdout.")
    var output: String?

    func run() throws {
        let types = try ProjectLoader.loadTypes(projectPath: path, includeBodyReferences: false)
            .sorted { ($0.filePath, $0.name) < ($1.filePath, $1.name) }

        switch format {
        case .text:
            let lines = types.map { "\($0.name) (\($0.kind.rawValue)) - \($0.filePath)" }
            try emit(lines.joined(separator: "\n"), to: output)
        case .json:
            try emit(GraphFormat.prettyJSON(types), to: output)
        }
    }
}
