import SDGECore
import SwiftUI

struct FileSidebarView: View {
    @ObservedObject var model: AppViewModel

    private var selection: Binding<SwiftSourceFile.ID?> {
        Binding(
            get: { model.selectedFile?.id },
            set: model.selectFile(id:)
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
                List {
                    OutlineGroup(model.filteredFileTree, children: \.outlineChildren) { node in
                        FileTreeRow(
                            node: node,
                            isSelected: node.file?.id == selection.wrappedValue,
                            select: { fileID in
                                model.selectFile(id: fileID)
                            }
                        )
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
    let isSelected: Bool
    let select: (SwiftSourceFile.ID) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.isFolder ? "folder" : "swift")
                .foregroundStyle(node.isFolder ? Color.secondary : Color.orange)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12))
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.18))
            }
        }
        .help(node.file?.path ?? node.name)
        .onTapGesture {
            guard let file = node.file else { return }
            select(file.id)
        }
    }
}
