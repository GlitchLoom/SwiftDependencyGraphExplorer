import Foundation
import XCTest
@testable import ProjectScanner

final class ProjectScannerTests: XCTestCase {
    func testScanReturnsSwiftFilesAndSkipsExcludedDirectories() throws {
        let root = try makeTempProject(files: [
            "Sources/App/Foo.swift": "struct Foo {}",
            ".build/Hidden.swift": "struct Hidden {}",
            "DerivedData/Generated.swift": "struct Generated {}",
            ".git/Ignored.swift": "struct GitType {}",
            "node_modules/Ignored.swift": "struct NodeType {}",
            ".swiftpm/Ignored.swift": "struct SwiftPMType {}",
            "Pods/Ignored.swift": "struct PodType {}",
            "Carthage/Ignored.swift": "struct CarthageType {}"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let files = try ProjectScanner().scan(rootURL: root)

        XCTAssertEqual(files.map(\.path), ["Sources/App/Foo.swift"])
        XCTAssertEqual(files.first?.contents, "struct Foo {}")
    }

    func testScanSortsIncludedSwiftFilesByRelativePath() throws {
        let root = try makeTempProject(files: [
            "Sources/App/Zoo.swift": "struct Zoo {}",
            "Sources/App/Alpha.swift": "struct Alpha {}",
            "Sources/Shared/Utility.swift": "struct Utility {}"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let files = try ProjectScanner().scan(rootURL: root)

        XCTAssertEqual(files.map(\.path), [
            "Sources/App/Alpha.swift",
            "Sources/App/Zoo.swift",
            "Sources/Shared/Utility.swift"
        ])
    }

    private func makeTempProject(files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SDGE-ProjectScanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for (relativePath, contents) in files {
            let fileURL = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return root
    }
}
