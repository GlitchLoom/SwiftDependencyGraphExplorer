import SDGECore
import XCTest
@testable import MermaidRenderer

final class MermaidGraphInteractionTests: XCTestCase {
    func testBuildsInteractionPayloadWithRootNodesAndStableEdgeIdentifiers() {
        let graph = DependencyGraph(
            nodes: [
                .init(name: "RootView", kind: .struct, isExternal: false),
                .init(name: "ProfileViewModel", kind: .class, isExternal: false),
                .init(name: "API.Client", kind: nil, isExternal: true)
            ],
            edges: [
                .init(source: "RootView", target: "ProfileViewModel", relationship: .property, isExternal: false, memberName: "viewModel"),
                .init(source: "ProfileViewModel", target: "API.Client", relationship: .methodReturn, isExternal: true, memberName: "makeClient")
            ]
        )

        let interaction = MermaidGraphInteraction(
            graph: graph,
            rootNodeName: "RootView",
            nodeIdentifiers: [
                "RootView": "RootView",
                "ProfileViewModel": "ProfileViewModel",
                "API.Client": "API_Client"
            ]
        )

        XCTAssertEqual(interaction.rootNodeName, "RootView")
        XCTAssertEqual(interaction.nodes.map(\.name), ["API.Client", "ProfileViewModel", "RootView"])
        XCTAssertEqual(interaction.edges.map(\.sourceName), ["ProfileViewModel", "RootView"])
        XCTAssertEqual(interaction.edges.map(\.targetMermaidID), ["API_Client", "ProfileViewModel"])
        XCTAssertEqual(interaction.edges.map(\.relationship), ["returns", "property"])
        XCTAssertEqual(interaction.edges.map(\.memberName), ["makeClient", "viewModel"])
    }

    func testRenderScriptDoesNotReturnAsyncPromiseToWebKit() {
        let script = MermaidRenderScript.build(
            source: "flowchart LR\nA --> B",
            generation: 7,
            interactionJSON: "{\"rootNodeName\":\"A\"}"
        )

        XCTAssertTrue(script.hasPrefix("void window.renderMermaid("))
        XCTAssertTrue(script.contains("\"flowchart LR\\nA --> B\""))
        XCTAssertTrue(script.contains(", 7, {\"rootNodeName\":\"A\"}"))
    }

    func testInteractionUpdateScriptDoesNotTriggerMermaidRender() {
        let script = MermaidRenderScript.buildInteractionUpdate(interactionJSON: "{\"rootNodeName\":\"A\"}")

        XCTAssertEqual(script, "window.setGraphInteraction({\"rootNodeName\":\"A\"})")
        XCTAssertFalse(script.contains("renderMermaid"))
        XCTAssertFalse(script.contains("resetZoom"))
    }

    @MainActor
    func testRendererHTMLKeepsClickDetectionSeparateFromPanGesture() {
        let html = MermaidWebView.testingHTML

        XCTAssertTrue(html.contains("const dragThreshold = 4;"))
        XCTAssertTrue(html.contains("htmlLabels: false"))
        XCTAssertTrue(html.contains("nodeSpacing: 80"))
        XCTAssertTrue(html.contains("rankSpacing: 110"))
        XCTAssertTrue(html.contains("pointer.targetNodeName"))
        XCTAssertTrue(html.contains("applyPathHighlight(pointer.targetNodeName)"))
        XCTAssertTrue(html.contains("collectIncomingEdges(targetName)"))
        XCTAssertTrue(html.contains("edge.querySelectorAll('path, line, polyline')"))
        XCTAssertFalse(html.contains("element.addEventListener('click'"))
        XCTAssertFalse(html.contains("viewport.addEventListener('click'"))
    }

    @MainActor
    func testRendererHTMLMarksTheSelectedRootNodeWithADistinctStyleIndependentOfPathHighlighting() {
        let html = MermaidWebView.testingHTML

        XCTAssertTrue(html.contains("element.classList.toggle('sdge-selected-node', node.name === graphInteraction.rootNodeName);"))
        XCTAssertTrue(html.contains(".sdge-selected-node rect"))
        XCTAssertTrue(html.contains("svg.sdge-path-active .sdge-selected-node"))
    }

    @MainActor
    func testRendererHTMLShowsAnEdgeDetailTooltipOnMarkerClickWithoutTriggeringNodeOrPanHandling() {
        let html = MermaidWebView.testingHTML

        XCTAssertTrue(html.contains("function renderEdgeMarkers()"))
        XCTAssertTrue(html.contains("class', 'sdge-edge-marker'"))
        XCTAssertTrue(html.contains("function detailLine(detail)"))
        XCTAssertTrue(html.contains("detail.memberName ? `${detail.relationship}: ${detail.memberName}` : detail.relationship"))
        XCTAssertTrue(html.contains("function edgeGroupIndexForElement(element)"))
        XCTAssertTrue(html.contains("const edgeGroupIndex = targetNodeName ? null : edgeGroupIndexForElement(event.target);"))
        XCTAssertTrue(html.contains("showEdgeTooltip(pointer.edgeGroupIndex, event.clientX, event.clientY);"))
        XCTAssertFalse(html.contains("marker.addEventListener('click'"))
    }

    @MainActor
    func testRendererHTMLDetectsANodeDoubleClickFromItsOwnPointerEventsInsteadOfNativeDblclick() {
        let html = MermaidWebView.testingHTML

        // The native 'dblclick' mouse event isn't used because WebKit may retarget it after
        // viewport.setPointerCapture() above redirects the pointer's own events; detecting the
        // second click from pointerdown/pointerup (which we already resolve to a node name
        // reliably) avoids depending on that.
        XCTAssertFalse(html.contains("addEventListener('dblclick'"))
        XCTAssertTrue(html.contains("const doubleClickThresholdMs = 400;"))
        XCTAssertTrue(html.contains("post({ type: 'nodeActivated', name: pointer.targetNodeName });"))
    }
}
