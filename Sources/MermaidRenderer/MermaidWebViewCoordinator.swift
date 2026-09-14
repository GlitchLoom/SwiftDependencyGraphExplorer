import SwiftUI
import WebKit

@MainActor
public final class MermaidWebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    weak var webView: WKWebView?
    var mermaidSource = ""
    var interactionGraph: MermaidGraphInteraction?
    var isLoaded = false
    private var renderedMermaidSource: String?
    private var renderingMermaidSource: String?
    private var renderedInteractionJSON: String?
    private var pageGeneration = 0
    private var renderGeneration = 0

    private var svgOutput: Binding<String>
    private let controller: MermaidWebViewController

    init(svgOutput: Binding<String>, controller: MermaidWebViewController) {
        self.svgOutput = svgOutput
        self.controller = controller
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        controller.connect(to: webView)
        verifyJavaScriptReadiness(in: webView, pageGeneration: pageGeneration)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoaded = false
        renderedMermaidSource = nil
        renderingMermaidSource = nil
        renderedInteractionJSON = nil
        pageGeneration += 1
        renderGeneration += 1
        svgOutput.wrappedValue = ""
        controller.setNotReady()
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        navigationFailed(error)
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        navigationFailed(error)
    }

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "mermaidRenderer",
              let payload = message.body as? [String: Any],
              let type = payload["type"] as? String else {
            return
        }

        switch type {
        case "rendered":
            guard payload["generation"] as? Int == renderGeneration,
                  payload["source"] as? String == mermaidSource else { return }
            svgOutput.wrappedValue = payload["svg"] as? String ?? ""
            renderedMermaidSource = mermaidSource
            renderedInteractionJSON = interactionJSON()
            renderingMermaidSource = nil
            controller.clearRendererError()
            controller.setCurrentSourceRendered(mermaidSource, generation: renderGeneration)
        case "error":
            guard payload["generation"] as? Int == renderGeneration,
                  payload["source"] as? String == mermaidSource else { return }
            svgOutput.wrappedValue = ""
            renderedMermaidSource = nil
            renderedInteractionJSON = nil
            renderingMermaidSource = nil
            controller.setRendererError(.renderingFailed(payload["message"] as? String ?? "Unknown Mermaid error"))
        case "nodeActivated":
            guard let name = payload["name"] as? String else { return }
            controller.nodeActivationHandler?(name)
        default:
            break
        }
    }

    func render() {
        let interaction = interactionJSON()
        guard let webView else {
            return
        }

        guard renderedMermaidSource != mermaidSource else {
            applyInteractionIfNeeded(interaction, in: webView)
            return
        }

        guard renderingMermaidSource != mermaidSource else {
            return
        }

        renderGeneration += 1
        let generation = renderGeneration
        let source = mermaidSource
        renderingMermaidSource = mermaidSource
        controller.setCurrentSourceRenderPending()
        webView.evaluateJavaScript(
            MermaidRenderScript.build(
                source: source,
                generation: generation,
                interactionJSON: interaction
            )
        ) { _, error in
            guard generation == self.renderGeneration else { return }
            if error != nil {
                self.svgOutput.wrappedValue = ""
                self.renderedMermaidSource = nil
                self.renderedInteractionJSON = nil
                self.renderingMermaidSource = nil
                self.controller.setNotReady(.renderingFailed(error?.localizedDescription ?? "Unable to execute Mermaid renderer"))
            }
        }
    }

    private func applyInteractionIfNeeded(_ interaction: String?, in webView: WKWebView) {
        guard renderedInteractionJSON != interaction else { return }
        let script = MermaidRenderScript.buildInteractionUpdate(interactionJSON: interaction)
        webView.evaluateJavaScript(script) { _, error in
            if error == nil {
                self.renderedInteractionJSON = interaction
            }
        }
    }

    private func interactionJSON() -> String? {
        guard let interactionGraph,
              let data = try? JSONEncoder().encode(interactionGraph) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func resourceUnavailable() {
        svgOutput.wrappedValue = ""
        controller.setNotReady(.bundledResourceUnavailable)
    }

    private func navigationFailed(_ error: Error) {
        isLoaded = false
        renderedMermaidSource = nil
        renderingMermaidSource = nil
        renderedInteractionJSON = nil
        pageGeneration += 1
        renderGeneration += 1
        svgOutput.wrappedValue = ""
        controller.setNotReady(.renderingFailed(error.localizedDescription))
    }

    private func verifyJavaScriptReadiness(in webView: WKWebView, pageGeneration: Int) {
        let check = """
        (() => {
          const required = ['renderMermaid', 'zoomIn', 'zoomOut', 'fitToScreen', 'resetZoom', 'currentSVG', 'clearPathHighlight', 'setGraphInteraction'];
          return typeof window.mermaid === 'object' &&
            typeof window.mermaid.render === 'function' &&
            required.every(name => typeof window[name] === 'function');
        })()
        """

        webView.evaluateJavaScript(check) { value, error in
            guard pageGeneration == self.pageGeneration else { return }

            guard error == nil, value as? Bool == true else {
                self.isLoaded = false
                self.svgOutput.wrappedValue = ""
                let message = error?.localizedDescription ?? "The bundled Mermaid script or renderer bridge did not load."
                self.controller.setNotReady(.renderingFailed(message))
                return
            }

            self.isLoaded = true
            self.controller.setReady()
            self.render()
        }
    }
}
