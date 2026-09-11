import Foundation
import SDGECore
import XCTest
@testable import SwiftDependencyGraphExplorerApp

@MainActor
final class AppViewModelTests: XCTestCase {
    func testSuggestedBaseFilenameUsesGenericNameWithoutSelectedType() {
        let model = AppViewModel(services: services(files: [], types: []))

        XCTAssertEqual(model.suggestedBaseFilename, "dependency-graph-depth-2")
    }

    func testSuggestedBaseFilenameUsesSelectedTypeAndDepth() async {
        let file = sourceFile(path: "Root.swift")
        let root = SwiftType(name: "Root", kind: .class, filePath: file.path)
        let model = AppViewModel(services: services(files: [file], types: [root]))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        model.options.depth = 4

        XCTAssertEqual(model.suggestedBaseFilename, "Root-depth-4")
    }

    func testOpenProjectIndexesFilesFiltersByPathAndAutoSelectsSingleType() async {
        let files = [
            sourceFile(path: "Sources/Features/ProfileView.swift"),
            sourceFile(path: "Sources/AppDelegate.swift")
        ]
        let profile = SwiftType(name: "ProfileView", kind: .struct, filePath: files[0].path)
        let appDelegate = SwiftType(name: "AppDelegate", kind: .class, filePath: files[1].path)
        let model = AppViewModel(services: services(files: files, types: [profile, appDelegate]))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))

        XCTAssertEqual(model.indexedFiles.map(\.path), files.map(\.path))
        XCTAssertEqual(model.selectedFile?.path, files[0].path)
        XCTAssertEqual(model.selectedType?.name, "ProfileView")

        model.searchText = "appdelegate"
        XCTAssertEqual(model.filteredFiles.map(\.path), ["Sources/AppDelegate.swift"])
    }

    func testFilteredFileTreeKeepsFolderHierarchyAndSortsLikeNavigator() async throws {
        let files = [
            sourceFile(path: "Sources/Features/ProfileView.swift"),
            sourceFile(path: "Tests/ProfileTests.swift"),
            sourceFile(path: "Sources/AppDelegate.swift")
        ]
        let model = AppViewModel(services: services(files: files, types: []))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))

        XCTAssertEqual(model.filteredFileTree.map(\.name), ["Sources", "Tests"])

        let sources = try XCTUnwrap(model.filteredFileTree.first { $0.name == "Sources" })
        XCTAssertEqual(sources.children.map(\.name), ["Features", "AppDelegate.swift"])

        let features = try XCTUnwrap(sources.children.first { $0.name == "Features" })
        XCTAssertEqual(features.children.map(\.name), ["ProfileView.swift"])
        XCTAssertEqual(features.children.first?.file?.path, "Sources/Features/ProfileView.swift")

        model.searchText = "profile"
        XCTAssertEqual(model.filteredFileTree.map(\.name), ["Sources", "Tests"])
        XCTAssertEqual(model.filteredFileTree.flatMap(\.leafFiles).map(\.path), [
            "Sources/Features/ProfileView.swift",
            "Tests/ProfileTests.swift"
        ])
    }

    func testOpenProjectMergesDependenciesFromCrossFileExtension() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SDGE-CrossFileExtension-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try "final class Foo {}".write(
            to: rootURL.appendingPathComponent("Foo.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        extension Foo: NetworkHandling {
            var client: Client { fatalError() }
            convenience init(delegate: Delegate) { self.init() }
            func send(_ request: Request) -> Response { fatalError() }
        }
        """.write(
            to: rootURL.appendingPathComponent("Foo+Networking.swift"),
            atomically: true,
            encoding: .utf8
        )

        let model = AppViewModel()

        await model.openProject(rootURL)

        let foo = try XCTUnwrap(model.allTypes.first { $0.name == "Foo" })
        XCTAssertEqual(foo.conformances, ["NetworkHandling"])
        XCTAssertTrue(foo.members.contains(.init(name: "client", typeName: "Client", kind: .property)))
        XCTAssertTrue(foo.members.contains(.init(name: "delegate", typeName: "Delegate", kind: .initializerParameter)))
        XCTAssertTrue(foo.members.contains(.init(name: "request", typeName: "Request", kind: .methodParameter)))
        XCTAssertTrue(foo.members.contains(.init(name: "send", typeName: "Response", kind: .methodReturn)))
    }

    func testSelectingFileWithMultipleTypesRequiresExplicitTypeSelection() async {
        let file = sourceFile(path: "Models.swift")
        let user = SwiftType(name: "User", kind: .struct, filePath: file.path)
        let session = SwiftType(name: "Session", kind: .class, filePath: file.path)
        let model = AppViewModel(services: services(files: [file], types: [user, session]))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))

        XCTAssertNil(model.selectedType)
        model.selectType(id: session.id)
        XCTAssertEqual(model.selectedType, session)
    }

    func testAnalyzeBuildsGraphAndMermaidForSelectedTypeAndOptions() async {
        let file = sourceFile(path: "Root.swift")
        let root = SwiftType(name: "Root", kind: .class, filePath: file.path)
        var capturedRoot = ""
        var capturedOptions = AnalysisOptions.defaults
        let expectedGraph = DependencyGraph(nodes: [
            DependencyNode(name: "Root", kind: .class, isExternal: false)
        ])
        let model = AppViewModel(services: AppServices(
            scanProject: { _ in [file] },
            parseFile: { _, _ in [root] },
            analyze: { rootTypeName, _, options in
                capturedRoot = rootTypeName
                capturedOptions = options
                return expectedGraph
            },
            buildMermaid: { _ in "flowchart LR\n    Root[\"Root\"]" }
        ))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        model.options.depth = 4
        model.options.includeSystemTypes = true
        model.options.includeThirdPartyTypes = false
        model.options.includeBodyReferences = true
        model.options.includeProtocols = false
        model.options.includeClasses = false
        model.options.includeStructs = false
        model.options.includeEnums = false
        model.options.excludedPrefixes = ["UI", "Test"]
        await model.analyze()

        XCTAssertEqual(capturedRoot, "Root")
        XCTAssertEqual(capturedOptions.depth, 4)
        XCTAssertTrue(capturedOptions.includeSystemTypes)
        XCTAssertFalse(capturedOptions.includeThirdPartyTypes)
        XCTAssertTrue(capturedOptions.includeBodyReferences)
        XCTAssertFalse(capturedOptions.includeProtocols)
        XCTAssertFalse(capturedOptions.includeClasses)
        XCTAssertFalse(capturedOptions.includeStructs)
        XCTAssertFalse(capturedOptions.includeEnums)
        XCTAssertEqual(capturedOptions.excludedPrefixes, ["UI", "Test"])
        XCTAssertEqual(model.graph, expectedGraph)
        XCTAssertEqual(model.mermaidSource, "flowchart LR\n    Root[\"Root\"]")
    }

    func testParserFailureIsReportedWithoutDiscardingOtherFiles() async {
        enum ParseFailure: LocalizedError {
            case invalidSyntax

            var errorDescription: String? { "Invalid syntax" }
        }

        let goodFile = sourceFile(path: "Good.swift")
        let badFile = sourceFile(path: "Bad.swift")
        let goodType = SwiftType(name: "Good", kind: .struct, filePath: goodFile.path)
        let model = AppViewModel(services: AppServices(
            scanProject: { _ in [badFile, goodFile] },
            parseFile: { file, _ in
                if file.path == badFile.path { throw ParseFailure.invalidSyntax }
                return [goodType]
            },
            analyze: { _, _, _ in DependencyGraph() },
            buildMermaid: { _ in "" }
        ))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))

        XCTAssertEqual(model.allTypes, [goodType])
        XCTAssertEqual(model.issue?.kind, .parser)
        XCTAssertTrue(model.issue?.message.contains("Bad.swift") == true)
    }

    func testOlderProjectLoadCannotOverwriteNewerProjectState() async {
        let firstURL = URL(fileURLWithPath: "/tmp/First")
        let secondURL = URL(fileURLWithPath: "/tmp/Second")
        let firstFile = sourceFile(path: "First.swift")
        let secondFile = sourceFile(path: "Second.swift")
        let firstType = SwiftType(name: "First", kind: .struct, filePath: firstFile.path)
        let secondType = SwiftType(name: "Second", kind: .struct, filePath: secondFile.path)
        let firstScanStarted = expectation(description: "First scan started")
        let firstScanGate = AsyncGate()
        let model = AppViewModel(services: AppServices(
            scanProject: { url in
                if url == firstURL {
                    firstScanStarted.fulfill()
                    await firstScanGate.wait()
                    return [firstFile]
                }
                return [secondFile]
            },
            parseFile: { file, _ in
                file.path == firstFile.path ? [firstType] : [secondType]
            },
            analyze: { _, _, _ in DependencyGraph() },
            buildMermaid: { _ in "" }
        ))

        let firstLoad = Task { await model.openProject(firstURL) }
        await fulfillment(of: [firstScanStarted], timeout: 1)
        await model.openProject(secondURL)
        await firstScanGate.open()
        await firstLoad.value

        XCTAssertEqual(model.selectedFolderURL, secondURL)
        XCTAssertEqual(model.indexedFiles.map(\.path), [secondFile.path])
        XCTAssertEqual(model.selectedType, secondType)
        XCTAssertFalse(model.isIndexing)
    }

    func testCancelledProjectLoadDoesNotResetCurrentProject() async {
        let currentURL = URL(fileURLWithPath: "/tmp/Current")
        let cancelledURL = URL(fileURLWithPath: "/tmp/Cancelled")
        let currentFile = sourceFile(path: "Current.swift")
        let currentType = SwiftType(name: "Current", kind: .struct, filePath: currentFile.path)
        let model = AppViewModel(services: services(files: [currentFile], types: [currentType]))

        await model.openProject(currentURL)
        let cancelledLoad = Task { await model.openProject(cancelledURL) }
        cancelledLoad.cancel()
        await cancelledLoad.value

        XCTAssertEqual(model.selectedFolderURL, currentURL)
        XCTAssertEqual(model.indexedFiles.map(\.path), [currentFile.path])
        XCTAssertEqual(model.selectedType, currentType)
    }

    func testChangingSelectionDuringAnalysisDiscardsOlderResult() async {
        let firstFile = sourceFile(path: "First.swift")
        let secondFile = sourceFile(path: "Second.swift")
        let firstType = SwiftType(name: "First", kind: .class, filePath: firstFile.path)
        let secondType = SwiftType(name: "Second", kind: .class, filePath: secondFile.path)
        let analysisStarted = expectation(description: "Analysis started")
        let analysisGate = AsyncGate()
        let staleGraph = DependencyGraph(nodes: [
            DependencyNode(name: firstType.name, kind: firstType.kind, isExternal: false)
        ])
        let model = AppViewModel(services: AppServices(
            scanProject: { _ in [firstFile, secondFile] },
            parseFile: { file, _ in
                file.path == firstFile.path ? [firstType] : [secondType]
            },
            analyze: { _, _, _ in
                analysisStarted.fulfill()
                await analysisGate.wait()
                return staleGraph
            },
            buildMermaid: { _ in "stale mermaid" }
        ))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        let analysis = Task { await model.analyze() }
        await fulfillment(of: [analysisStarted], timeout: 1)
        model.selectFile(id: secondFile.id)
        await analysisGate.open()
        await analysis.value

        XCTAssertEqual(model.selectedType, secondType)
        XCTAssertNil(model.graph)
        XCTAssertTrue(model.mermaidSource.isEmpty)
        XCTAssertFalse(model.isAnalyzing)
    }

    func testChangingOptionsDuringAnalysisDiscardsOlderResult() async {
        let file = sourceFile(path: "Root.swift")
        let root = SwiftType(name: "Root", kind: .class, filePath: file.path)
        let analysisStarted = expectation(description: "Analysis started")
        let analysisGate = AsyncGate()
        let staleGraph = DependencyGraph(nodes: [
            DependencyNode(name: root.name, kind: root.kind, isExternal: false)
        ])
        let model = AppViewModel(services: AppServices(
            scanProject: { _ in [file] },
            parseFile: { _, _ in [root] },
            analyze: { _, _, _ in
                analysisStarted.fulfill()
                await analysisGate.wait()
                return staleGraph
            },
            buildMermaid: { _ in "stale mermaid" }
        ))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        let analysis = Task { await model.analyze() }
        await fulfillment(of: [analysisStarted], timeout: 1)
        model.options.depth = 4
        await analysisGate.open()
        await analysis.value

        XCTAssertNil(model.graph)
        XCTAssertTrue(model.mermaidSource.isEmpty)
        XCTAssertFalse(model.isAnalyzing)
    }

    func testSelectedDuplicateNameTypeIsFirstAnalyzerInput() async {
        let firstFile = sourceFile(path: "FeatureA/Shared.swift")
        let secondFile = sourceFile(path: "FeatureB/Shared.swift")
        let firstShared = SwiftType(name: "Shared", kind: .class, filePath: firstFile.path)
        let selectedShared = SwiftType(name: "Shared", kind: .struct, filePath: secondFile.path)
        var analyzerInput: [SwiftType] = []
        let model = AppViewModel(services: AppServices(
            scanProject: { _ in [firstFile, secondFile] },
            parseFile: { file, _ in
                file.path == firstFile.path ? [firstShared] : [selectedShared]
            },
            analyze: { _, types, _ in
                analyzerInput = types
                return DependencyGraph()
            },
            buildMermaid: { _ in "flowchart LR" }
        ))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        model.selectFile(id: secondFile.id)
        await model.analyze()

        XCTAssertEqual(analyzerInput.map(\.id), [selectedShared.id, firstShared.id])
    }

    func testParserWarningPersistsThroughAnalysisWithoutReparse() async {
        enum ParseFailure: LocalizedError {
            case invalidSyntax

            var errorDescription: String? { "Invalid syntax" }
        }

        let goodFile = sourceFile(path: "Good.swift")
        let badFile = sourceFile(path: "Bad.swift")
        let goodType = SwiftType(name: "Good", kind: .struct, filePath: goodFile.path)
        let model = AppViewModel(services: AppServices(
            scanProject: { _ in [goodFile, badFile] },
            parseFile: { file, _ in
                if file.path == badFile.path { throw ParseFailure.invalidSyntax }
                return [goodType]
            },
            analyze: { _, _, _ in DependencyGraph() },
            buildMermaid: { _ in "flowchart LR" }
        ))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        await model.analyze()

        XCTAssertEqual(model.issue?.kind, .parser)
        XCTAssertTrue(model.issue?.message.contains("Bad.swift") == true)
    }

    func testSuccessfulReparseClearsEarlierParserWarning() async {
        enum ParseFailure: LocalizedError {
            case invalidSyntax

            var errorDescription: String? { "Invalid syntax" }
        }

        let goodFile = sourceFile(path: "Good.swift")
        let badFile = sourceFile(path: "Bad.swift")
        let goodType = SwiftType(name: "Good", kind: .struct, filePath: goodFile.path)
        let model = AppViewModel(services: AppServices(
            scanProject: { _ in [goodFile, badFile] },
            parseFile: { file, includeBodyReferences in
                if file.path == badFile.path && !includeBodyReferences {
                    throw ParseFailure.invalidSyntax
                }
                return file.path == goodFile.path ? [goodType] : []
            },
            analyze: { _, _, _ in DependencyGraph() },
            buildMermaid: { _ in "flowchart LR" }
        ))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        XCTAssertEqual(model.issue?.kind, .parser)

        model.options.includeBodyReferences = true
        await model.analyze()

        XCTAssertNil(model.issue)
    }

    func testActivateTypeDrillsInBySwitchingSelectionToTheNamedTypeAndReanalyzing() async {
        let firstFile = sourceFile(path: "First.swift")
        let secondFile = sourceFile(path: "Second.swift")
        let firstType = SwiftType(name: "First", kind: .class, filePath: firstFile.path)
        let secondType = SwiftType(name: "Second", kind: .struct, filePath: secondFile.path)
        var capturedRoots: [String] = []
        let model = AppViewModel(services: AppServices(
            scanProject: { _ in [firstFile, secondFile] },
            parseFile: { file, _ in file.path == firstFile.path ? [firstType] : [secondType] },
            analyze: { rootTypeName, _, _ in
                capturedRoots.append(rootTypeName)
                return DependencyGraph(nodes: [DependencyNode(name: rootTypeName, kind: nil, isExternal: false)])
            },
            buildMermaid: { graph in "flowchart LR\n    \(graph.nodes.first?.name ?? "")" }
        ))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        XCTAssertEqual(model.selectedType?.name, "First")

        await model.activateType(named: "Second")

        XCTAssertEqual(model.selectedFile?.path, secondFile.path)
        XCTAssertEqual(model.selectedType, secondType)
        XCTAssertEqual(capturedRoots, ["Second"])
        XCTAssertEqual(model.mermaidSource, "flowchart LR\n    Second")
    }

    func testActivateTypeIsANoOpForNamesThatDoNotResolveToAParsedType() async {
        let file = sourceFile(path: "Root.swift")
        let root = SwiftType(name: "Root", kind: .class, filePath: file.path)
        let model = AppViewModel(services: services(files: [file], types: [root]))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        await model.analyze()
        let graphBeforeActivation = model.graph

        await model.activateType(named: "SomeExternalType")

        XCTAssertEqual(model.selectedType, root)
        XCTAssertEqual(model.graph, graphBeforeActivation)
    }

    func testBackAndForwardNavigateThroughTheAnalyzedRootTypeHistory() async {
        let fileA = sourceFile(path: "A.swift")
        let fileB = sourceFile(path: "B.swift")
        let fileC = sourceFile(path: "C.swift")
        let typeA = SwiftType(name: "A", kind: .struct, filePath: fileA.path)
        let typeB = SwiftType(name: "B", kind: .struct, filePath: fileB.path)
        let typeC = SwiftType(name: "C", kind: .struct, filePath: fileC.path)
        let model = AppViewModel(services: services(files: [fileA, fileB, fileC], types: [typeA, typeB, typeC]))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        await model.analyze()
        XCTAssertEqual(model.selectedType?.name, "A")
        XCTAssertFalse(model.canNavigateBack)
        XCTAssertFalse(model.canNavigateForward)

        // A no-op back/forward at the edges of history shouldn't change the current selection.
        await model.navigateBack()
        await model.navigateForward()
        XCTAssertEqual(model.selectedType?.name, "A")

        await model.activateType(named: "B")
        XCTAssertEqual(model.selectedType?.name, "B")
        XCTAssertTrue(model.canNavigateBack)
        XCTAssertFalse(model.canNavigateForward)

        await model.activateType(named: "C")
        XCTAssertEqual(model.selectedType?.name, "C")

        await model.navigateBack()
        XCTAssertEqual(model.selectedType?.name, "B")
        XCTAssertTrue(model.canNavigateBack)
        XCTAssertTrue(model.canNavigateForward)

        await model.navigateBack()
        XCTAssertEqual(model.selectedType?.name, "A")
        XCTAssertFalse(model.canNavigateBack)
        XCTAssertTrue(model.canNavigateForward)

        await model.navigateForward()
        XCTAssertEqual(model.selectedType?.name, "B")
        XCTAssertTrue(model.canNavigateForward)

        // Visiting a new type after going back discards the stale forward entry, browser-style.
        await model.activateType(named: "C")
        XCTAssertFalse(model.canNavigateForward)
    }

    func testOpeningANewProjectResetsNavigationHistory() async {
        let fileA = sourceFile(path: "A.swift")
        let fileB = sourceFile(path: "B.swift")
        let typeA = SwiftType(name: "A", kind: .struct, filePath: fileA.path)
        let typeB = SwiftType(name: "B", kind: .struct, filePath: fileB.path)
        let model = AppViewModel(services: services(files: [fileA, fileB], types: [typeA, typeB]))

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample"))
        await model.analyze()
        await model.activateType(named: "B")
        XCTAssertTrue(model.canNavigateBack)

        await model.openProject(URL(fileURLWithPath: "/tmp/Sample2"))

        XCTAssertFalse(model.canNavigateBack)
        XCTAssertFalse(model.canNavigateForward)
    }

    private func sourceFile(path: String) -> SwiftSourceFile {
        SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Sample").appendingPathComponent(path),
            path: path,
            contents: ""
        )
    }

    private func services(files: [SwiftSourceFile], types: [SwiftType]) -> AppServices {
        AppServices(
            scanProject: { _ in files },
            parseFile: { file, _ in types.filter { $0.filePath == file.path } },
            analyze: { _, _, _ in DependencyGraph() },
            buildMermaid: { _ in "flowchart LR" }
        )
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                self.continuation = continuation
            }
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
