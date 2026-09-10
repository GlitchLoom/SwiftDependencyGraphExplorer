import SDGECore

struct FileTreeNode: Equatable, Identifiable {
    let id: String
    let name: String
    let file: SwiftSourceFile?
    let children: [FileTreeNode]

    var outlineChildren: [FileTreeNode]? {
        children.isEmpty ? nil : children
    }

    var leafFiles: [SwiftSourceFile] {
        if let file {
            return [file]
        }
        return children.flatMap(\.leafFiles)
    }

    var isFolder: Bool {
        file == nil
    }
}

enum FileTreeBuilder {
    static func build(from files: [SwiftSourceFile]) -> [FileTreeNode] {
        let root = MutableFileTreeNode(name: "", path: "", file: nil)
        files.forEach { root.insert(file: $0) }
        return root.sortedChildren()
    }
}

private final class MutableFileTreeNode {
    let name: String
    let path: String
    var file: SwiftSourceFile?
    var children: [String: MutableFileTreeNode] = [:]

    init(name: String, path: String, file: SwiftSourceFile?) {
        self.name = name
        self.path = path
        self.file = file
    }

    func insert(file: SwiftSourceFile) {
        let components = file.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else { return }
        insert(file: file, components: components, index: 0)
    }

    private func insert(file: SwiftSourceFile, components: [String], index: Int) {
        let component = components[index]
        let childPath = path.isEmpty ? component : "\(path)/\(component)"
        let isLeaf = index == components.indices.last
        let child = children[component] ?? MutableFileTreeNode(
            name: component,
            path: childPath,
            file: isLeaf ? file : nil
        )

        if isLeaf {
            child.file = file
        } else {
            child.insert(file: file, components: components, index: index + 1)
        }

        children[component] = child
    }

    func sortedChildren() -> [FileTreeNode] {
        children.values
            .sorted { lhs, rhs in
                switch (lhs.file == nil, rhs.file == nil) {
                case (true, false):
                    return true
                case (false, true):
                    return false
                default:
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
            .map { child in
                FileTreeNode(
                    id: child.file?.id ?? "folder:\(child.path)",
                    name: child.name,
                    file: child.file,
                    children: child.sortedChildren()
                )
            }
    }
}
