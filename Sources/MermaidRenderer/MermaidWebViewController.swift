import WebKit

@MainActor
public final class MermaidWebViewController: ObservableObject {
    weak var webView: WKWebView?
    @Published public private(set) var isReady = false
    @Published public private(set) var isCurrentSourceRendered = false
    @Published public private(set) var rendererError: MermaidRendererError?

    /// Invoked with a node's name when the user double-clicks it in the diagram, to let the
    /// host re-center the analysis on that type ("drill in").
    public var nodeActivationHandler: ((String) -> Void)?

    private var pendingScripts: [String] = []
    private var renderedMermaidSource: String?
    private var renderedGeneration: Int?

    public init() {}

    public func zoomIn() {
        run("window.zoomIn()")
    }

    public func zoomOut() {
        run("window.zoomOut()")
    }

    public func fitToScreen() {
        run("window.fitToScreen()")
    }

    public func resetZoom() {
        run("window.resetZoom()")
    }

    public func clearHighlight() {
        run("window.clearPathHighlight()")
    }

    public func currentSVG() async throws -> String {
        guard let webView else {
            throw MermaidRendererError.webViewUnavailable
        }
        if let rendererError {
            throw rendererError
        }
        guard isReady else {
            throw MermaidRendererError.notReady
        }
        guard isCurrentSourceRendered else {
            throw MermaidRendererError.currentSourceNotRendered
        }

        let value = try await webView.evaluateJavaScript("window.currentSVG()")
        guard let svg = value as? String, !svg.isEmpty else {
            throw MermaidRendererError.svgUnavailable
        }
        return svg
    }

    public func currentSVG(for mermaidSource: String) async throws -> String {
        guard hasRendered(mermaidSource), let generation = renderedGeneration else {
            throw MermaidRendererError.currentSourceNotRendered
        }

        guard let webView else {
            throw MermaidRendererError.webViewUnavailable
        }
        if let rendererError {
            throw rendererError
        }
        guard isReady else {
            throw MermaidRendererError.notReady
        }

        let script = MermaidRenderScript.currentSVG(source: mermaidSource, generation: generation)
        let value = try await webView.evaluateJavaScript(script)
        guard let svg = value as? String, !svg.isEmpty else {
            throw MermaidRendererError.currentSourceNotRendered
        }
        guard hasRendered(mermaidSource), renderedGeneration == generation else {
            throw MermaidRendererError.currentSourceNotRendered
        }
        return svg
    }

    public func hasRendered(_ mermaidSource: String) -> Bool {
        isCurrentSourceRendered && renderedMermaidSource == mermaidSource
    }

    func connect(to webView: WKWebView) {
        self.webView = webView
    }

    func setReady() {
        isReady = true
        let scripts = pendingScripts
        pendingScripts.removeAll()
        scripts.forEach { execute($0) }
    }

    func setNotReady(_ error: MermaidRendererError? = nil) {
        isReady = false
        isCurrentSourceRendered = false
        renderedMermaidSource = nil
        renderedGeneration = nil
        rendererError = error
    }

    func setCurrentSourceRenderPending() {
        isCurrentSourceRendered = false
        renderedMermaidSource = nil
        renderedGeneration = nil
        rendererError = nil
    }

    func setCurrentSourceRendered(_ mermaidSource: String, generation: Int) {
        renderedMermaidSource = mermaidSource
        renderedGeneration = generation
        isCurrentSourceRendered = true
    }

    func setRendererError(_ error: MermaidRendererError) {
        isCurrentSourceRendered = false
        renderedMermaidSource = nil
        renderedGeneration = nil
        rendererError = error
    }

    func clearRendererError() {
        rendererError = nil
    }

    private func run(_ script: String) {
        guard isReady else {
            pendingScripts.append(script)
            return
        }
        execute(script)
    }

    private func execute(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
}
