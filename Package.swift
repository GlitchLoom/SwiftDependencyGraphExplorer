// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftDependencyGraphExplorer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SwiftDependencyGraphExplorer", targets: ["SwiftDependencyGraphExplorerApp"]),
        .library(name: "SDGECore", targets: ["SDGECore"]),
        .library(name: "ProjectScanner", targets: ["ProjectScanner"]),
        .library(name: "SwiftTypeParser", targets: ["SwiftTypeParser"]),
        .library(name: "DependencyAnalyzer", targets: ["DependencyAnalyzer"]),
        .library(name: "GraphBuilder", targets: ["GraphBuilder"]),
        .library(name: "MermaidRenderer", targets: ["MermaidRenderer"])
    ],
    targets: [
        .target(name: "SDGECore"),
        .target(name: "ProjectScanner", dependencies: ["SDGECore"]),
        .target(name: "SwiftTypeParser", dependencies: ["SDGECore"]),
        .target(name: "DependencyAnalyzer", dependencies: ["SDGECore"]),
        .target(name: "GraphBuilder", dependencies: ["SDGECore"]),
        .target(
            name: "MermaidRenderer",
            dependencies: ["SDGECore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "SwiftDependencyGraphExplorerApp",
            dependencies: ["SDGECore", "ProjectScanner", "SwiftTypeParser", "DependencyAnalyzer", "GraphBuilder", "MermaidRenderer"]
        ),
        .testTarget(name: "SDGECoreTests", dependencies: ["SDGECore"]),
        .testTarget(name: "ProjectScannerTests", dependencies: ["ProjectScanner", "SDGECore"]),
        .testTarget(name: "SwiftTypeParserTests", dependencies: ["SwiftTypeParser", "SDGECore"]),
        .testTarget(name: "DependencyAnalyzerTests", dependencies: ["DependencyAnalyzer", "SDGECore"]),
        .testTarget(name: "GraphBuilderTests", dependencies: ["GraphBuilder", "SDGECore"]),
        .testTarget(name: "MermaidRendererTests", dependencies: ["MermaidRenderer", "SDGECore"]),
        .testTarget(
            name: "SwiftDependencyGraphExplorerAppTests",
            dependencies: ["SwiftDependencyGraphExplorerApp", "SDGECore"]
        )
    ]
)
