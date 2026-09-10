import AppKit
import SwiftUI

struct MermaidSourceView: View {
    let source: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Generated Mermaid")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: copySource) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(source.isEmpty)
                .help("Copy Mermaid source")
            }
            .padding(.horizontal, 10)
            .frame(height: 38)

            Divider()

            if source.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("No Mermaid source")
                        .font(.headline)
                    Text("Run an analysis to generate source.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(source)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private func copySource() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
        copied = true

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
