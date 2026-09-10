import XCTest
import SDGECore
@testable import GraphBuilder

final class MermaidGraphBuilderTests: XCTestCase {
    func testBuildsStableMermaidFlowchartWithoutVisibleEdgeLabels() {
        let graph = DependencyGraph(
            nodes: [
                .init(name: "ViewModel", kind: .class, isExternal: false),
                .init(name: "UserService", kind: .protocol, isExternal: false)
            ],
            edges: [
                .init(source: "ViewModel", target: "UserService", relationship: .property, isExternal: false)
            ]
        )

        let mermaid = MermaidGraphBuilder().buildMermaid(from: graph)

        XCTAssertTrue(mermaid.hasPrefix("flowchart LR"))
        XCTAssertTrue(mermaid.contains("ViewModel[\"ViewModel\"]"))
        XCTAssertTrue(mermaid.contains("UserService[\"UserService\"]"))
        XCTAssertTrue(mermaid.contains("ViewModel --> UserService"))
        XCTAssertFalse(mermaid.contains("-->|property|"))
    }

    func testSortsNodesAndEdgesWithoutRenderingRelationshipLabels() {
        let graph = DependencyGraph(
            nodes: [
                .init(name: "Zed", kind: .class, isExternal: false),
                .init(name: "Alpha", kind: .protocol, isExternal: false),
                .init(name: "Middle", kind: .struct, isExternal: false)
            ],
            edges: [
                .init(source: "Zed", target: "Middle", relationship: .bodyReference, isExternal: false),
                .init(source: "Zed", target: "Alpha", relationship: .conforms, isExternal: false),
                .init(source: "Zed", target: "Middle", relationship: .methodReturn, isExternal: false),
                .init(source: "Zed", target: "Middle", relationship: .methodParameter, isExternal: false),
                .init(source: "Zed", target: "Middle", relationship: .initializerParameter, isExternal: false),
                .init(source: "Zed", target: "Middle", relationship: .inherits, isExternal: false)
            ]
        )

        let mermaid = MermaidGraphBuilder().buildMermaid(from: graph)
        let lines = mermaid.split(separator: "\n").map(String.init)

        XCTAssertEqual(Array(lines[1...3]), [
            "    Alpha[\"Alpha\"]",
            "    Middle[\"Middle\"]",
            "    Zed[\"Zed\"]"
        ])
        XCTAssertTrue(mermaid.contains("Zed --> Alpha"))
        XCTAssertTrue(mermaid.contains("Zed --> Middle"))
        XCTAssertFalse(mermaid.contains("|inherits|"))
        XCTAssertFalse(mermaid.contains("|conforms|"))
        XCTAssertFalse(mermaid.contains("|init parameter|"))
        XCTAssertFalse(mermaid.contains("|method parameter|"))
        XCTAssertFalse(mermaid.contains("|returns|"))
        XCTAssertFalse(mermaid.contains("|body reference|"))
    }

    func testSanitizesIdentifiersEscapesLabelsAndStylesExternalNodes() {
        let graph = DependencyGraph(
            nodes: [
                .init(name: "Local Type", kind: .class, isExternal: false),
                .init(name: "UIKit.UIView", kind: nil, isExternal: true)
            ],
            edges: [
                .init(source: "Local Type", target: "UIKit.UIView", relationship: .property, isExternal: true)
            ]
        )

        let mermaid = MermaidGraphBuilder().buildMermaid(from: graph)

        XCTAssertTrue(mermaid.contains("Local_Type[\"Local Type\"]"))
        XCTAssertTrue(mermaid.contains("UIKit_UIView[\"UIKit.UIView\"]"))
        XCTAssertTrue(mermaid.contains("class UIKit_UIView external"))
        XCTAssertTrue(mermaid.contains("classDef external"))
    }

    func testPublishesTheSameStableNodeIdentifiersUsedByMermaidSource() {
        let graph = DependencyGraph(
            nodes: [
                .init(name: "Local Type", kind: .class, isExternal: false),
                .init(name: "Local.Type", kind: .struct, isExternal: false)
            ]
        )

        let builder = MermaidGraphBuilder()
        let identifiers = builder.nodeIdentifiers(for: graph)
        let mermaid = builder.buildMermaid(from: graph)

        XCTAssertEqual(identifiers["Local Type"], "Local_Type")
        XCTAssertEqual(identifiers["Local.Type"], "Local_Type_2")
        XCTAssertTrue(mermaid.contains("Local_Type[\"Local Type\"]"))
        XCTAssertTrue(mermaid.contains("Local_Type_2[\"Local.Type\"]"))
    }

    func testBuildsDOTWithQuotedLabelsAndStableOrdering() {
        let graph = DependencyGraph(
            nodes: [
                .init(name: "Zed", kind: .class, isExternal: false),
                .init(name: "Alpha", kind: .protocol, isExternal: false)
            ],
            edges: [
                .init(source: "Zed", target: "Alpha", relationship: .property, isExternal: false)
            ]
        )

        let dot = MermaidGraphBuilder().buildDOT(from: graph)

        XCTAssertTrue(dot.hasPrefix("digraph DependencyGraph {"))
        XCTAssertTrue(dot.contains("    \"Alpha\" [label=\"Alpha\"];"))
        XCTAssertTrue(dot.contains("    \"Zed\" [label=\"Zed\"];"))
        XCTAssertTrue(dot.contains("    \"Zed\" -> \"Alpha\" [label=\"property\"];"))
    }
}
