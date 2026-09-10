import Foundation

enum MermaidRenderScript {
    static func build(source: String, generation: Int, interactionJSON: String?) -> String {
        "void window.renderMermaid(\(javaScriptLiteral(source)), \(generation), \(interactionJSON ?? "null"))"
    }

    static func buildInteractionUpdate(interactionJSON: String?) -> String {
        "window.setGraphInteraction(\(interactionJSON ?? "null"))"
    }

    private static func javaScriptLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              var encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        encoded.removeFirst()
        encoded.removeLast()
        return encoded
    }
}
