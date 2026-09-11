import SDGECore
import SwiftUI

struct FileSidebarView: View {
    @ObservedObject var model: AppViewModel

    /// The List's native selection. Tags every row (files and folders) with the tree node's own
    /// id so AppKit drives the real Navigator-style selection pill, but only forwards the change
    /// to the view model when it actually resolves to a file -- clicking a folder just expands
    /// it, the way Xcode's Navigator does, rather than clearing the current file.
    private var selection: Binding<String?> {
        Binding(
            get: { model.selectedFile?.id },
            set: { newValue in
                guard let newValue, model.indexedFiles.contains(where: { $0.id == newValue }) else { return }
                model.selectFile(id: newValue)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isIndexing {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Indexing Swift files...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.indexedFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.ellipsis")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No Swift files found")
                        .font(.headline)
                    Text("Choose another project folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No matching files")
                        .font(.headline)
                    Text("Try another search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .searchable(text: $model.searchText, prompt: "Search files")
            } else {
                List(selection: selection) {
                    OutlineGroup(model.filteredFileTree, children: \.outlineChildren) { node in
                        FileTreeRow(node: node)
                            .tag(node.id)
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $model.searchText, prompt: "Search files")
            }

            Divider()
            Text(fileCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.selectedFolderURL?.lastPathComponent ?? "Project")
                .font(.headline)
                .lineLimit(1)
            Text(model.selectedFolderURL?.path ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private var fileCountText: String {
        let visible = model.filteredFiles.count
        let total = model.indexedFiles.count
        return visible == total ? "\(total) Swift files" : "\(visible) of \(total) Swift files"
    }
}

private struct FileTreeRow: View {
    let node: FileTreeNode

    var body: some View {
        Label {
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: node.isFolder ? "folder.fill" : "swift")
                .foregroundStyle(node.isFolder ? Color.secondary : Color.orange)
        }
        .help(node.file?.path ?? node.name)
    }
}
