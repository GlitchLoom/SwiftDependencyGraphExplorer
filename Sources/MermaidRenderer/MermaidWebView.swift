import AppKit
import SwiftUI
import WebKit

@MainActor
public struct MermaidWebView: NSViewRepresentable {
    public typealias NSViewType = WKWebView

    private let mermaidSource: String
    private let interactionGraph: MermaidGraphInteraction?
    @Binding private var svgOutput: String
    public let controller: MermaidWebViewController

    public init(
        mermaidSource: String,
        interactionGraph: MermaidGraphInteraction? = nil,
        svgOutput: Binding<String>,
        controller: MermaidWebViewController
    ) {
        self.mermaidSource = mermaidSource
        self.interactionGraph = interactionGraph
        _svgOutput = svgOutput
        self.controller = controller
    }

    public init(mermaidSource: String, svgOutput: Binding<String>) {
        self.init(
            mermaidSource: mermaidSource,
            interactionGraph: nil,
            svgOutput: svgOutput,
            controller: MermaidWebViewController()
        )
    }

    public func makeCoordinator() -> MermaidWebViewCoordinator {
        MermaidWebViewCoordinator(svgOutput: $svgOutput, controller: controller)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "mermaidRenderer")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        context.coordinator.webView = webView
        controller.connect(to: webView)

        guard let scriptURL = Bundle.module.url(forResource: "mermaid.min", withExtension: "js") else {
            context.coordinator.resourceUnavailable()
            return webView
        }

        webView.loadHTMLString(MermaidHTMLTemplate.source, baseURL: scriptURL.deletingLastPathComponent())
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.mermaidSource = mermaidSource
        context.coordinator.interactionGraph = interactionGraph
        if context.coordinator.isLoaded {
            context.coordinator.render()
        }
    }

    public static func dismantleNSView(_ nsView: WKWebView, coordinator: MermaidWebViewCoordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "mermaidRenderer")
        nsView.navigationDelegate = nil
    }

    static var testingHTML: String {
        MermaidHTMLTemplate.source
    }
}
