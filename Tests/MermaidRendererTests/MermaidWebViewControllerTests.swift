import XCTest
@testable import MermaidRenderer

@MainActor
final class MermaidWebViewControllerTests: XCTestCase {
    func testInitialStateIsNotReadyWithNoRendererError() {
        let controller = MermaidWebViewController()

        XCTAssertFalse(controller.isReady)
        XCTAssertFalse(controller.isCurrentSourceRendered)
        XCTAssertNil(controller.rendererError)
        XCTAssertFalse(controller.hasRendered("flowchart LR\nA --> B"))
    }

    func testCurrentSVGThrowsWebViewUnavailableWhenNoWebViewIsConnected() async {
        let controller = MermaidWebViewController()

        await XCTAssertThrowsErrorAsync(try await controller.currentSVG()) { error in
            XCTAssertEqual(error as? MermaidRendererError, .webViewUnavailable)
        }
    }

    func testCurrentSVGForSourceThrowsCurrentSourceNotRenderedWhenThatSourceWasNeverRendered() async {
        let controller = MermaidWebViewController()

        await XCTAssertThrowsErrorAsync(try await controller.currentSVG(for: "flowchart LR\nA --> B")) { error in
            XCTAssertEqual(error as? MermaidRendererError, .currentSourceNotRendered)
        }
    }

    func testHasRenderedTracksTheMostRecentlyRenderedSourceOnly() {
        let controller = MermaidWebViewController()

        controller.setCurrentSourceRendered("flowchart LR\nA --> B", generation: 1)

        XCTAssertTrue(controller.hasRendered("flowchart LR\nA --> B"))
        XCTAssertFalse(controller.hasRendered("flowchart LR\nA --> C"))
        XCTAssertTrue(controller.isCurrentSourceRendered)
    }

    func testSetReadyMarksTheControllerReady() {
        let controller = MermaidWebViewController()

        controller.setReady()

        XCTAssertTrue(controller.isReady)
    }

    func testSetNotReadyClearsReadinessRenderedStateAndStoresTheError() {
        let controller = MermaidWebViewController()
        controller.setReady()
        controller.setCurrentSourceRendered("flowchart LR\nA --> B", generation: 1)

        controller.setNotReady(.bundledResourceUnavailable)

        XCTAssertFalse(controller.isReady)
        XCTAssertFalse(controller.isCurrentSourceRendered)
        XCTAssertFalse(controller.hasRendered("flowchart LR\nA --> B"))
        XCTAssertEqual(controller.rendererError, .bundledResourceUnavailable)
    }

    func testSetCurrentSourceRenderPendingClearsRenderedStateWithoutTouchingReadiness() {
        let controller = MermaidWebViewController()
        controller.setReady()
        controller.setCurrentSourceRendered("flowchart LR\nA --> B", generation: 1)

        controller.setCurrentSourceRenderPending()

        XCTAssertTrue(controller.isReady)
        XCTAssertFalse(controller.isCurrentSourceRendered)
        XCTAssertFalse(controller.hasRendered("flowchart LR\nA --> B"))
        XCTAssertNil(controller.rendererError)
    }

    func testSetRendererErrorClearsRenderedStateButKeepsTheControllerReady() {
        let controller = MermaidWebViewController()
        controller.setReady()
        controller.setCurrentSourceRendered("flowchart LR\nA --> B", generation: 1)

        controller.setRendererError(.renderingFailed("boom"))

        XCTAssertTrue(controller.isReady)
        XCTAssertFalse(controller.isCurrentSourceRendered)
        XCTAssertFalse(controller.hasRendered("flowchart LR\nA --> B"))
        XCTAssertEqual(controller.rendererError, .renderingFailed("boom"))
    }

    func testClearRendererErrorRemovesAPreviouslyStoredError() {
        let controller = MermaidWebViewController()
        controller.setRendererError(.renderingFailed("boom"))

        controller.clearRendererError()

        XCTAssertNil(controller.rendererError)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
