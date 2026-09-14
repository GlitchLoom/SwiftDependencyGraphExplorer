import Foundation

public enum MermaidRendererError: LocalizedError, Equatable {
    case webViewUnavailable
    case notReady
    case bundledResourceUnavailable
    case svgUnavailable
    case currentSourceNotRendered
    case renderingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .webViewUnavailable:
            return "The Mermaid web view is not available."
        case .notReady:
            return "The Mermaid renderer is not ready yet."
        case .bundledResourceUnavailable:
            return "The bundled mermaid.min.js resource is unavailable."
        case .svgUnavailable:
            return "The rendered diagram does not contain an SVG."
        case .currentSourceNotRendered:
            return "The current Mermaid source has not finished rendering."
        case .renderingFailed(let message):
            return "Mermaid failed to render the diagram: \(message)"
        }
    }
}
