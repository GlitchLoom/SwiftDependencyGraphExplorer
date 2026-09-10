import Foundation
import SDGECore

public struct ProjectScanner {
    private let fileManager: FileManager
    private let skippedDirectoryNames: Set<String> = [
        ".build",
        ".git",
        "Carthage",
        "DerivedData",
        "node_modules",
        "Pods"
    ]

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(rootURL: URL) throws -> [SwiftSourceFile] {
        let rootURL = rootURL.standardizedFileURL
        let rootPath = rootURL.path
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options,
            errorHandler: { _, _ in true }
        )

        var files: [SwiftSourceFile] = []

        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: resourceKeys)

            if values.isDirectory == true {
                if url.lastPathComponent.hasPrefix(".") || skippedDirectoryNames.contains(url.lastPathComponent) {
                    enumerator?.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true, url.pathExtension == "swift" else {
                continue
            }

            let contents = try String(contentsOf: url, encoding: .utf8)
            let relativePath = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
            files.append(SwiftSourceFile(url: url, path: relativePath, contents: contents))
        }

        return files.sorted { $0.path < $1.path }
    }
}
