import Foundation
import SDGECore
import XCTest
@testable import SDGECLI

final class SDGECLITests: XCTestCase {
    func testParseExcludedPrefixesSplitsTrimsAndDropsEmptyEntries() {
        XCTAssertEqual(parseExcludedPrefixes("UI, NS ,Test"), ["UI", "NS", "Test"])
        XCTAssertEqual(parseExcludedPrefixes(""), [])
        XCTAssertEqual(parseExcludedPrefixes("  ,  "), [])
    }

    func testDirectionOptionMapsToAnalysisDirection() {
        XCTAssertEqual(DirectionOption.uses.analysisDirection, .uses)
        XCTAssertEqual(DirectionOption.usedBy.analysisDirection, .usedBy)
        XCTAssertEqual(DirectionOption.both.analysisDirection, .both)
        XCTAssertEqual(DirectionOption(argument: "used-by"), .usedBy)
    }

    func testGraphFormatRendersMermaidDotAndJSON() throws {
        let graph = DependencyGraph(
            nodes: [DependencyNode(name: "A", kind: .struct, isExternal: false)],
            edges: []
        )

        XCTAssertTrue(try GraphFormat.mermaid.render(graph).contains("A[\"A\"]"))
        XCTAssertTrue(try GraphFormat.dot.render(graph).contains("\"A\""))

        let json = try GraphFormat.json.render(graph)
        let decoded = try JSONDecoder().decode(DependencyGraph.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, graph)
    }

    func testProjectLoaderScansParsesAndReconcilesExtensionsAcrossFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SDGECLITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "final class Service {}".write(
            to: root.appendingPathComponent("Service.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "extension Service: Codable { var extra: ExtraDep { fatalError() } }".write(
            to: root.appendingPathComponent("ServiceExtension.swift"),
            atomically: true,
            encoding: .utf8
        )

        let types = try ProjectLoader.loadTypes(projectPath: root.path, includeBodyReferences: false)
        let service = try XCTUnwrap(types.first { $0.name == "Service" })

        XCTAssertTrue(service.conformances.contains("Codable"))
        XCTAssertTrue(service.members.contains(SwiftMember(name: "extra", typeName: "ExtraDep", kind: .property)))
    }

    func testAnalyzeCommandRejectsAnUnknownRootType() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SDGECLITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "struct Known {}".write(
            to: root.appendingPathComponent("Known.swift"),
            atomically: true,
            encoding: .utf8
        )

        let command = try Analyze.parse(["--path", root.path, "--root-type", "Missing"])
        XCTAssertThrowsError(try command.run())
    }
}
