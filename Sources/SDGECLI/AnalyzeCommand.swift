import ArgumentParser
import DependencyAnalyzer
import Foundation
import SDGECore

struct Analyze: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Build a type dependency graph rooted at a given type."
    )

    @Option(name: .shortAndLong, help: "Path to the Swift project's root folder.")
    var path: String = FileManager.default.currentDirectoryPath

    @Option(name: [.customLong("root-type"), .customShort("t")], help: "The type to center the dependency graph on.")
    var rootType: String

    @Option(help: "How many hops to expand from the root type.")
    var depth: Int = 2

    @Option(help: "Direction to expand in: uses, used-by, or both.")
    var direction: DirectionOption = .uses

    @Flag(inversion: .prefixedNo, help: "Include Swift/Apple system types (Foundation, UIKit, ...) in the graph.")
    var includeSystemTypes: Bool = false

    @Flag(inversion: .prefixedNo, help: "Include third-party (non-local, non-system) types in the graph.")
    var includeThirdPartyTypes: Bool = true

    @Flag(inversion: .prefixedNo, help: "Also track types referenced only inside function/closure bodies.")
    var includeBodyReferences: Bool = false

    @Flag(inversion: .prefixedNo, help: "Include protocol types.")
    var includeProtocols: Bool = true

    @Flag(inversion: .prefixedNo, help: "Include class types.")
    var includeClasses: Bool = true

    @Flag(inversion: .prefixedNo, help: "Include struct types.")
    var includeStructs: Bool = true

    @Flag(inversion: .prefixedNo, help: "Include enum types.")
    var includeEnums: Bool = true

    @Option(help: "Comma-separated name prefixes to exclude, e.g. \"UI,NS,Test\".")
    var excludedPrefixes: String = ""

    @Option(help: "Output format: mermaid, dot, or json.")
    var format: GraphFormat = .mermaid

    @Option(name: .shortAndLong, help: "Write output to this file instead of stdout.")
    var output: String?

    func run() throws {
        let types = try ProjectLoader.loadTypes(projectPath: path, includeBodyReferences: includeBodyReferences)

        guard types.contains(where: { $0.name == rootType }) else {
            throw ValidationError(
                "No type named \"\(rootType)\" was found under \(path). " +
                "Run `sdge list-types --path \(path)` to see the available types."
            )
        }

        // AnalysisOptions has no public memberwise initializer, so build on `.defaults` and
        // override each field -- all of them are mutable `var` properties.
        var options = AnalysisOptions.defaults
        options.depth = depth
        options.direction = direction.analysisDirection
        options.includeSystemTypes = includeSystemTypes
        options.includeThirdPartyTypes = includeThirdPartyTypes
        options.includeBodyReferences = includeBodyReferences
        options.includeProtocols = includeProtocols
        options.includeClasses = includeClasses
        options.includeStructs = includeStructs
        options.includeEnums = includeEnums
        options.excludedPrefixes = parseExcludedPrefixes(excludedPrefixes)

        let graph = DependencyAnalyzer().analyze(rootTypeName: rootType, types: types, options: options)
        try emit(format.render(graph), to: output)
    }
}
