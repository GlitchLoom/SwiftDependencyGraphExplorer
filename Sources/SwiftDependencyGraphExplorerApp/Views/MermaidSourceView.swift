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
                editor
            }
        }
    }

    /// Mimics Xcode's source editor: a fixed-width line-number gutter that scrolls vertically in
    /// lockstep with the text but stays pinned horizontally while the code itself scrolls
    /// sideways -- hence the nested ScrollViews (outer vertical for both, inner horizontal for
    /// just the text column).
    private var editor: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                lineNumberGutter
                ScrollView(.horizontal) {
                    Text(source)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var lineNumberGutter: some View {
        let lineCount = max(1, source.components(separatedBy: "\n").count)
        return VStack(alignment: .trailing, spacing: 0) {
            ForEach(1...lineCount, id: \.self) { line in
                Text("\(line)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) {
            Divider()
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
