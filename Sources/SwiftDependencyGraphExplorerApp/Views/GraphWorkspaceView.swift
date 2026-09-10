import AppKit
import GraphBuilder
import MermaidRenderer
import SwiftUI
import UniformTypeIdentifiers

struct GraphWorkspaceView: View {
    private enum WorkspaceTab: Hashable {
        case graph
        case source
    }

    @ObservedObject var model: AppViewModel
    @StateObject private var rendererController = MermaidWebViewController()
    @State private var svgOutput = ""
    @State private var selectedTab: WorkspaceTab = .graph
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let issue = model.issue {
                IssueBanner(issue: issue, onDismiss: model.clearIssue)
                Divider()
            }

            TabView(selection: $selectedTab) {
                graphTab
                    .tabItem { Label("Graph", systemImage: "point.3.connected.trianglepath.dotted") }
                    .tag(WorkspaceTab.graph)

                MermaidSourceView(source: model.mermaidSource)
                    .tabItem { Label("Mermaid Source", systemImage: "chevron.left.forwardslash.chevron.right") }
                    .tag(WorkspaceTab.source)
            }
            .padding(.top, 4)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Export Failed", isPresented: exportErrorIsPresented) {
            Button("OK", role: .cancel) {
                exportError = nil
            }
        } message: {
            Text(exportError ?? "")
        }
        .onAppear {
            rendererController.nodeActivationHandler = { name in
                Task { await model.activateType(named: name) }
            }
        }
    }

    private var graphTab: some View {
        VStack(spacing: 0) {
            graphControls
            Divider()
            graphContent
        }
    }

    private var graphControls: some View {
        HStack(spacing: 4) {
            Text(graphTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            exportMenu
            graphControlButton("Zoom In", systemImage: "plus.magnifyingglass", action: rendererController.zoomIn)
            graphControlButton("Zoom Out", systemImage: "minus.magnifyingglass", action: rendererController.zoomOut)
            graphControlButton("Fit to Screen", systemImage: "arrow.up.left.and.arrow.down.right", action: rendererController.fitToScreen)
            graphControlButton("Reset Zoom", systemImage: "arrow.counterclockwise", action: rendererController.resetZoom)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }

    private var exportMenu: some View {
        Menu {
            Button("Export SVG...", action: exportSVG)
                .disabled(!rendererController.hasRendered(model.mermaidSource))
            Button("Export Mermaid...", action: exportMermaid)
                .disabled(model.mermaidSource.isEmpty)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .help("Export graph")
        .accessibilityLabel("Export graph")
    }

    @ViewBuilder
    private var graphContent: some View {
        if model.isIndexing {
            WorkspaceStateView(
                title: "Indexing project",
                message: "Reading Swift source files and discovering types.",
                systemImage: "doc.text.magnifyingglass",
                showsProgress: true
            )
        } else if model.indexedFiles.isEmpty {
            WorkspaceStateView(
                title: "No Swift files found",
                message: "Choose a folder containing Swift source files.",
                systemImage: "doc.badge.ellipsis"
            )
        } else if model.allTypes.isEmpty {
            WorkspaceStateView(
                title: "No Swift types found",
                message: "The indexed files did not contain supported type declarations.",
                systemImage: "curlybraces"
            )
        } else if model.isAnalyzing {
            WorkspaceStateView(
                title: "Building dependency graph",
                message: "Analyzing references from the selected root type.",
                systemImage: "point.3.connected.trianglepath.dotted",
                showsProgress: true
            )
        } else if model.mermaidSource.isEmpty {
            WorkspaceStateView(
                title: model.selectedType == nil ? "Select a root type" : "Ready to analyze",
                message: model.selectedType == nil
                    ? "Choose a file and type, then configure the analysis options."
                    : "Run the analysis to generate the dependency graph.",
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        } else {
            ZStack(alignment: .bottom) {
                MermaidWebView(
                    mermaidSource: model.mermaidSource,
                    interactionGraph: interactionGraph,
                    svgOutput: $svgOutput,
                    controller: rendererController
                )

                if let error = rendererController.rendererError {
                    RendererErrorBanner(message: error.localizedDescription)
                        .padding(12)
                }
            }
        }
    }

    private var graphTitle: String {
        guard let selectedType = model.selectedType else { return "Dependency Graph" }
        return "Dependency Graph: \(selectedType.name)"
    }

    private var interactionGraph: MermaidGraphInteraction? {
        guard let graph = model.graph else { return nil }
        return MermaidGraphInteraction(
            graph: graph,
            rootNodeName: model.selectedType?.name,
            nodeIdentifiers: MermaidGraphBuilder().nodeIdentifiers(for: graph)
        )
    }

    private func graphControlButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .disabled(model.mermaidSource.isEmpty || !rendererController.isReady)
        .help(title)
        .accessibilityLabel(title)
    }

    private var exportErrorIsPresented: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { isPresented in
                if !isPresented {
                    exportError = nil
                }
            }
        )
    }

    private func exportMermaid() {
        guard let url = exportURL(
            defaultName: "\(model.suggestedBaseFilename).mmd",
            contentType: UTType(filenameExtension: "mmd") ?? .plainText
        ) else {
            return
        }

        do {
            try model.mermaidSource.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportSVG() {
        Task {
            do {
                let mermaidSource = model.mermaidSource
                let defaultName = "\(model.suggestedBaseFilename).svg"
                let svg = try await rendererController.currentSVG(for: mermaidSource)
                guard model.mermaidSource == mermaidSource else {
                    throw MermaidRendererError.currentSourceNotRendered
                }
                guard let url = exportURL(
                    defaultName: defaultName,
                    contentType: .svg
                ) else {
                    return
                }
                try svg.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func exportURL(defaultName: String, contentType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true

        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct WorkspaceStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var showsProgress = false

    var body: some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct IssueBanner: View {
    let issue: AppIssue
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(issue.message)
                .font(.caption)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss error")
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct RendererErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.octagon.fill")
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.red.opacity(0.45))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
