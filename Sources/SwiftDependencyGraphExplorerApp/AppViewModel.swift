import AppKit
import DependencyAnalyzer
import Foundation
import GraphBuilder
import ProjectScanner
import SDGECore
import SwiftTypeParser

struct AppServices {
    var scanProject: (URL) async throws -> [SwiftSourceFile]
    var parseFile: (SwiftSourceFile, Bool) async throws -> [SwiftType]
    var reconcileProject: ([SwiftType], [SwiftSourceFile], Bool) async throws -> [SwiftType] = { types, _, _ in types }
    var analyze: (String, [SwiftType], AnalysisOptions) async -> DependencyGraph
    var buildMermaid: (DependencyGraph) -> String

    static let live = AppServices(
        scanProject: { rootURL in
            try await Task.detached {
                try ProjectScanner().scan(rootURL: rootURL)
            }.value
        },
        parseFile: { file, includeBodyReferences in
            try await Task.detached {
                try SwiftSyntaxTypeParser().parse(
                    file: file,
                    includeBodyReferences: includeBodyReferences
                )
            }.value
        },
        reconcileProject: { types, files, includeBodyReferences in
            try await Task.detached {
                try SwiftSyntaxTypeParser().reconcileProject(
                    types: types,
                    files: files,
                    includeBodyReferences: includeBodyReferences
                )
            }.value
        },
        analyze: { rootTypeName, types, options in
            await Task.detached {
                DependencyAnalyzer().analyze(
                    rootTypeName: rootTypeName,
                    types: types,
                    options: options
                )
            }.value
        },
        buildMermaid: { graph in
            MermaidGraphBuilder().buildMermaid(from: graph)
        }
    )
}

struct AppIssue: Identifiable, Equatable {
    enum Kind: Equatable {
        case indexing
        case parser
        case analysis
    }

    let kind: Kind
    let message: String
    var id: String { "\(kind)-\(message)" }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var selectedFolderURL: URL?
    @Published private(set) var indexedFiles: [SwiftSourceFile] = []
    @Published var searchText = ""
    @Published private(set) var selectedFile: SwiftSourceFile?
    @Published private(set) var parsedTypes: [SwiftType] = []
    @Published private(set) var selectedType: SwiftType?
    @Published var options = AnalysisOptions.defaults {
        didSet {
            if oldValue != options {
                invalidateAnalysis()
            }
        }
    }
    @Published private(set) var graph: DependencyGraph?
    @Published private(set) var mermaidSource = ""
    @Published private(set) var isIndexing = false
    @Published private(set) var isAnalyzing = false
    @Published private(set) var issue: AppIssue?
    @Published private(set) var canNavigateBack = false
    @Published private(set) var canNavigateForward = false

    private(set) var allTypes: [SwiftType] = []

    private let services: AppServices
    private var projectTask: Task<Void, Never>?
    private var projectGeneration = 0
    private var analysisGeneration = 0
    private var lastParsedIncludeBodyReferences = AnalysisOptions.defaults.includeBodyReferences

    /// Back/forward history of successfully analyzed root types, browser-style: analyzing a new
    /// type pushes the previous one onto `backHistory` and clears `forwardHistory`; navigating
    /// back/forward moves an entry between the two stacks without touching the other.
    private var backHistory: [SwiftType.ID] = []
    private var forwardHistory: [SwiftType.ID] = []
    private var currentHistoryEntry: SwiftType.ID?
    private var isNavigatingHistory = false

    init(services: AppServices = .live) {
        self.services = services
    }

    var filteredFiles: [SwiftSourceFile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return indexedFiles }
        return indexedFiles.filter { $0.path.localizedCaseInsensitiveContains(query) }
    }

    var filteredFileTree: [FileTreeNode] {
        FileTreeBuilder.build(from: filteredFiles)
    }

    var canAnalyze: Bool {
        selectedType != nil && !isIndexing && !isAnalyzing
    }

    var suggestedBaseFilename: String {
        let name = selectedType?.name ?? "dependency-graph"
        return "\(name)-depth-\(options.depth)"
    }

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Swift project folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        projectTask?.cancel()
        projectTask = Task { [weak self] in
            await self?.openProject(url)
        }
    }

    func openProject(_ rootURL: URL) async {
        guard !Task.isCancelled else { return }
        projectGeneration &+= 1
        let generation = projectGeneration
        let includeBodyReferences = options.includeBodyReferences
        reset(for: rootURL)
        isIndexing = true
        defer {
            if generation == projectGeneration {
                isIndexing = false
            }
        }

        do {
            let files = try await services.scanProject(rootURL)
            guard generation == projectGeneration, !Task.isCancelled else { return }

            let result = await parse(files: files, includeBodyReferences: includeBodyReferences)
            guard generation == projectGeneration, !Task.isCancelled else { return }

            indexedFiles = files
            allTypes = result.types
            lastParsedIncludeBodyReferences = includeBodyReferences

            if !result.failures.isEmpty {
                issue = AppIssue(kind: .parser, message: parserMessage(for: result.failures))
            }

            selectFile(indexedFiles.first)
        } catch is CancellationError {
            return
        } catch {
            guard generation == projectGeneration else { return }
            issue = AppIssue(kind: .indexing, message: error.localizedDescription)
        }
    }

    func selectFile(id: SwiftSourceFile.ID?) {
        selectFile(indexedFiles.first { $0.id == id })
    }

    func selectType(id: SwiftType.ID?) {
        selectedType = parsedTypes.first { $0.id == id }
        invalidateAnalysis()
    }

    /// Re-centers the analysis on the named type, as if the user had picked it as the new root
    /// and pressed Analyze. Used to "drill in" from a node in the rendered graph. A no-op for
    /// names that don't resolve to a locally parsed type (e.g. external/system dependencies),
    /// since there is nothing local to show.
    func activateType(named name: String) async {
        guard let type = allTypes.first(where: { $0.name == name }) else { return }
        await activate(type: type)
    }

    /// Re-analyzes the previously visited root type, the way a browser's back button reloads
    /// the previous page. No-op if there's nothing behind the current graph in the history.
    func navigateBack() async {
        guard let previous = backHistory.popLast() else { return }
        guard let current = currentHistoryEntry, let type = allTypes.first(where: { $0.id == previous }) else {
            backHistory.append(previous)
            return
        }

        forwardHistory.append(current)
        currentHistoryEntry = previous
        isNavigatingHistory = true
        await activate(type: type)
        isNavigatingHistory = false
        updateHistoryFlags()
    }

    /// The forward counterpart of `navigateBack()`. No-op if there's nothing ahead.
    func navigateForward() async {
        guard let next = forwardHistory.popLast() else { return }
        guard let current = currentHistoryEntry, let type = allTypes.first(where: { $0.id == next }) else {
            forwardHistory.append(next)
            return
        }

        backHistory.append(current)
        currentHistoryEntry = next
        isNavigatingHistory = true
        await activate(type: type)
        isNavigatingHistory = false
        updateHistoryFlags()
    }

    private func activate(type: SwiftType) async {
        selectFile(indexedFiles.first { $0.path == type.filePath })
        selectedType = parsedTypes.first { $0.id == type.id } ?? type
        invalidateAnalysis()
        await analyze()
    }

    func analyze() async {
        guard let rootType = selectedType else { return }
        analysisGeneration &+= 1
        let generation = analysisGeneration
        let originatingProjectGeneration = projectGeneration
        let optionsSnapshot = options

        isAnalyzing = true
        if issue?.kind == .analysis {
            issue = nil
        }
        clearAnalysis()
        defer {
            if generation == analysisGeneration {
                isAnalyzing = false
            }
        }

        if optionsSnapshot.includeBodyReferences != lastParsedIncludeBodyReferences {
            let result = await parse(
                files: indexedFiles,
                includeBodyReferences: optionsSnapshot.includeBodyReferences
            )
            guard isCurrentAnalysis(
                generation: generation,
                projectGeneration: originatingProjectGeneration,
                rootTypeID: rootType.id,
                options: optionsSnapshot
            ), !Task.isCancelled else { return }

            allTypes = result.types
            lastParsedIncludeBodyReferences = optionsSnapshot.includeBodyReferences
            refreshSelection(rootTypeID: rootType.id)

            if result.failures.isEmpty {
                if issue?.kind == .parser {
                    issue = nil
                }
            } else {
                issue = AppIssue(kind: .parser, message: parserMessage(for: result.failures))
            }
        }

        guard isCurrentAnalysis(
            generation: generation,
            projectGeneration: originatingProjectGeneration,
            rootTypeID: rootType.id,
            options: optionsSnapshot
        ), !Task.isCancelled else { return }

        guard let activeRootType = allTypes.first(where: { $0.id == rootType.id }) else {
            issue = AppIssue(kind: .analysis, message: "The selected type could not be parsed.")
            return
        }

        let orderedTypes = [activeRootType] + allTypes.filter { $0.id != activeRootType.id }
        let result = await services.analyze(activeRootType.name, orderedTypes, optionsSnapshot)
        guard isCurrentAnalysis(
            generation: generation,
            projectGeneration: originatingProjectGeneration,
            rootTypeID: rootType.id,
            options: optionsSnapshot
        ), !Task.isCancelled else { return }

        graph = result
        mermaidSource = services.buildMermaid(result)

        if !isNavigatingHistory {
            recordHistoryVisit(to: activeRootType.id)
        }
        updateHistoryFlags()
    }

    func clearIssue() {
        issue = nil
    }

    private func reset(for rootURL: URL) {
        invalidateAnalysis()
        selectedFolderURL = rootURL
        indexedFiles = []
        searchText = ""
        selectedFile = nil
        parsedTypes = []
        selectedType = nil
        allTypes = []
        issue = nil
        backHistory = []
        forwardHistory = []
        currentHistoryEntry = nil
        updateHistoryFlags()
    }

    /// Records a completed analysis in the back/forward history. A re-visit of the type
    /// currently at the top of history (e.g. re-analyzing after only changing options) updates
    /// it in place rather than pushing a duplicate entry. Visiting an actually different type
    /// clears `forwardHistory`, matching how a browser discards forward history once you
    /// navigate somewhere new instead of using the forward button.
    private func recordHistoryVisit(to id: SwiftType.ID) {
        defer { currentHistoryEntry = id }
        guard let current = currentHistoryEntry, current != id else { return }
        backHistory.append(current)
        forwardHistory.removeAll()
    }

    private func updateHistoryFlags() {
        canNavigateBack = !backHistory.isEmpty
        canNavigateForward = !forwardHistory.isEmpty
    }

    private func selectFile(_ file: SwiftSourceFile?) {
        selectedFile = file
        parsedTypes = allTypes
            .filter { $0.filePath == file?.path }
            .sorted { ($0.name, $0.kind.rawValue) < ($1.name, $1.kind.rawValue) }
        selectedType = parsedTypes.count == 1 ? parsedTypes[0] : nil
        invalidateAnalysis()
    }

    private func refreshSelection(rootTypeID: SwiftType.ID) {
        guard let selectedFile else { return }
        parsedTypes = allTypes
            .filter { $0.filePath == selectedFile.path }
            .sorted { ($0.name, $0.kind.rawValue) < ($1.name, $1.kind.rawValue) }
        selectedType = parsedTypes.first { $0.id == rootTypeID }
    }

    private func clearAnalysis() {
        graph = nil
        mermaidSource = ""
    }

    private func invalidateAnalysis() {
        analysisGeneration &+= 1
        isAnalyzing = false
        clearAnalysis()
    }

    private func isCurrentAnalysis(
        generation: Int,
        projectGeneration: Int,
        rootTypeID: SwiftType.ID,
        options: AnalysisOptions
    ) -> Bool {
        generation == analysisGeneration &&
            projectGeneration == self.projectGeneration &&
            selectedType?.id == rootTypeID &&
            self.options == options
    }

    private func parse(
        files: [SwiftSourceFile],
        includeBodyReferences: Bool
    ) async -> (types: [SwiftType], failures: [(path: String, error: Error)]) {
        var types: [SwiftType] = []
        var failures: [(path: String, error: Error)] = []

        for file in files {
            guard !Task.isCancelled else { break }
            do {
                types += try await services.parseFile(file, includeBodyReferences)
            } catch is CancellationError {
                break
            } catch {
                failures.append((file.path, error))
            }
        }

        guard !Task.isCancelled else { return (types, failures) }
        do {
            types = try await services.reconcileProject(types, files, includeBodyReferences)
        } catch is CancellationError {
            return (types, failures)
        } catch {
            failures.append(("Project extensions", error))
        }

        return (types, failures)
    }

    private func parserMessage(for failures: [(path: String, error: Error)]) -> String {
        let details = failures.prefix(3).map { "\($0.path): \($0.error.localizedDescription)" }
        let remainder = failures.count - details.count
        let suffix = remainder > 0 ? "\n...and \(remainder) more." : ""
        return "Some Swift files could not be parsed:\n\(details.joined(separator: "\n"))\(suffix)"
    }
}
