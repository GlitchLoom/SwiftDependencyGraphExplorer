import Foundation
import ProjectScanner
import SDGECore
import SwiftTypeParser

/// Shared scan-parse-reconcile pipeline, reused by every subcommand. Mirrors what
/// `AppServices.live` does for the GUI app, minus the SwiftUI-facing progress/cancellation
/// plumbing a one-shot CLI invocation doesn't need.
enum ProjectLoader {
    static func loadTypes(projectPath: String, includeBodyReferences: Bool) throws -> [SwiftType] {
        let rootURL = URL(fileURLWithPath: projectPath)
        let files = try ProjectScanner().scan(rootURL: rootURL)
        let parser = SwiftSyntaxTypeParser()

        var types: [SwiftType] = []
        for file in files {
            types += try parser.parse(file: file, includeBodyReferences: includeBodyReferences)
        }

        return try parser.reconcileProject(types: types, files: files, includeBodyReferences: includeBodyReferences)
    }
}
