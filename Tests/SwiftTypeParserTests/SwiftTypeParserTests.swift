import Foundation
import XCTest
import SDGECore
@testable import SwiftTypeParser

final class SwiftTypeParserTests: XCTestCase {
    func testParsesDeclarationsMembersAndMergesExtensions() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/ViewModel.swift"),
            path: "App/ViewModel.swift",
            contents: """
            import Foundation

            final class ViewModel: BaseViewModel, ObservableObject {
                let service: UserService
                init(service: UserService, cache: CacheStore) {}
                func load(id: UserID) -> User { service.fetch(id) }
            }

            extension ViewModel {
                var formatter: DateFormatter { DateFormatter() }
                func save(_ user: User) {}
            }

            struct User {}
            enum Screen {}
            protocol CacheStore {}
            actor Worker {}
            """
        )

        let types = try SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false)
        let viewModel = try XCTUnwrap(types.first { $0.name == "ViewModel" })

        XCTAssertEqual(types.map(\.kind).sorted { $0.rawValue < $1.rawValue }, [.actor, .class, .enum, .protocol, .struct])
        XCTAssertEqual(viewModel.inheritedTypes, ["BaseViewModel"])
        XCTAssertEqual(viewModel.conformances, ["ObservableObject"])
        XCTAssertTrue(viewModel.members.contains(SwiftMember(name: "service", typeName: "UserService", kind: .property)))
        XCTAssertTrue(viewModel.members.contains(SwiftMember(name: "service", typeName: "UserService", kind: .initializerParameter)))
        XCTAssertTrue(viewModel.members.contains(SwiftMember(name: "cache", typeName: "CacheStore", kind: .initializerParameter)))
        XCTAssertTrue(viewModel.members.contains(SwiftMember(name: "id", typeName: "UserID", kind: .methodParameter)))
        XCTAssertTrue(viewModel.members.contains(SwiftMember(name: "load", typeName: "User", kind: .methodReturn)))
        XCTAssertTrue(viewModel.members.contains(SwiftMember(name: "formatter", typeName: "DateFormatter", kind: .property)))
    }

    func testBodyReferencesAreOnlyParsedWhenEnabled() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/A.swift"),
            path: "A.swift",
            contents: "struct A { func make() { Helper().run() } }"
        )

        let disabled = try SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false)
        let enabled = try SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: true)

        XCTAssertFalse(disabled[0].members.contains { $0.kind == .bodyReference && $0.typeName == "Helper" })
        XCTAssertTrue(enabled[0].members.contains { $0.kind == .bodyReference && $0.typeName == "Helper" })
    }

    func testBodyReferencesInsidePropertyInitializerClosuresAreOnlyParsedWhenEnabled() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Services.swift"),
            path: "Services.swift",
            contents: """
            struct Services {
                static let live: Services = Services(
                    analyze: {
                        DependencyAnalyzer().run()
                    }
                )
                let analyze: () -> Void
            }
            """
        )

        let disabled = try SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false)
        let enabled = try SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: true)

        XCTAssertFalse(disabled[0].members.contains { $0.kind == .bodyReference })
        XCTAssertTrue(enabled[0].members.contains(SwiftMember(name: "DependencyAnalyzer", typeName: "DependencyAnalyzer", kind: .bodyReference)))
    }

    func testIgnoresDeclarationsInsideComments() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Comments.swift"),
            path: "Comments.swift",
            contents: """
            // class LineCommentedOut {}
            /* struct BlockCommentedOut {
                /* enum NestedCommentedOut {} */
            } */
            struct Visible {}
            """
        )

        let types = try SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false)

        XCTAssertEqual(types.map(\.name), ["Visible"])
    }

    func testIgnoresDelimitersAndDeclarationsInsideStringLiterals() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Strings.swift"),
            path: "Strings.swift",
            contents: """
            struct Container {
                let template: String = "struct Phantom { }"
                func make() -> Output { Factory() }
            }
            struct Following {}
            """
        )

        let types = try SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: true)
        let container = try XCTUnwrap(types.first { $0.name == "Container" })

        XCTAssertEqual(types.map(\.name), ["Container", "Following"])
        XCTAssertTrue(container.members.contains(SwiftMember(name: "make", typeName: "Output", kind: .methodReturn)))
        XCTAssertTrue(container.members.contains(SwiftMember(name: "Factory", typeName: "Factory", kind: .bodyReference)))
    }

    func testParsesGenericContainersAndCandidates() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Generics.swift"),
            path: "Generics.swift",
            contents: """
            class Child: Base<Model>, ChildProtocol {
                let repository: Repository<User>
                func load() -> Result<User, LoadError> { fatalError() }
            }
            """
        )

        let child = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false).first)

        XCTAssertEqual(child.inheritedTypes, ["Base", "Model"])
        XCTAssertEqual(child.conformances, ["ChildProtocol"])
        XCTAssertTrue(child.members.contains(SwiftMember(name: "repository", typeName: "Repository", kind: .property)))
        XCTAssertTrue(child.members.contains(SwiftMember(name: "repository", typeName: "User", kind: .property)))
        XCTAssertTrue(child.members.contains(SwiftMember(name: "load", typeName: "Result", kind: .methodReturn)))
        XCTAssertTrue(child.members.contains(SwiftMember(name: "load", typeName: "User", kind: .methodReturn)))
        XCTAssertTrue(child.members.contains(SwiftMember(name: "load", typeName: "LoadError", kind: .methodReturn)))
    }

    func testClassWithProtocolOnlyClauseMergesExtensionConformances() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Conformances.swift"),
            path: "Conformances.swift",
            contents: """
            final class ViewModel: ObservableObject {}
            extension ViewModel: ViewModelDelegate {}
            """
        )

        let viewModel = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false).first)

        XCTAssertEqual(viewModel.inheritedTypes, [])
        XCTAssertEqual(viewModel.conformances, ["ObservableObject", "ViewModelDelegate"])
    }

    func testParametersUseDeclaredTypesBeforeDefaultExpressions() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Defaults.swift"),
            path: "Defaults.swift",
            contents: """
            struct Configurator {
                init(service: Service = DefaultService()) {}
                func configure(service: Service = DefaultService()) {}
            }
            """
        )

        let configurator = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false).first)

        XCTAssertTrue(configurator.members.contains(SwiftMember(name: "service", typeName: "Service", kind: .initializerParameter)))
        XCTAssertTrue(configurator.members.contains(SwiftMember(name: "service", typeName: "Service", kind: .methodParameter)))
        XCTAssertFalse(configurator.members.contains { $0.typeName == "DefaultService" })
    }

    func testMultilineMethodBodyReferencesAreParsed() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Multiline.swift"),
            path: "Multiline.swift",
            contents: """
            struct Builder {
                func make()
                {
                    Factory()
                }
            }
            """
        )

        let builder = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: true).first)

        XCTAssertTrue(builder.members.contains(SwiftMember(name: "Factory", typeName: "Factory", kind: .bodyReference)))
    }

    func testBodylessProtocolRequirementsDoNotBorrowLaterReturnTypes() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Requirements.swift"),
            path: "Requirements.swift",
            contents: """
            protocol Worker {
                func prepare()
                func load() -> Payload
            }
            """
        )

        let worker = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false).first)

        XCTAssertFalse(worker.members.contains(SwiftMember(name: "prepare", typeName: "Payload", kind: .methodReturn)))
        XCTAssertTrue(worker.members.contains(SwiftMember(name: "load", typeName: "Payload", kind: .methodReturn)))
    }

    func testSemicolonSeparatedProtocolRequirementsDoNotBorrowReturnTypes() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/InlineRequirements.swift"),
            path: "InlineRequirements.swift",
            contents: "protocol InlineWorker { func prepare(); func load() -> Payload }"
        )

        let worker = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false).first)

        XCTAssertFalse(worker.members.contains(SwiftMember(name: "prepare", typeName: "Payload", kind: .methodReturn)))
        XCTAssertTrue(worker.members.contains(SwiftMember(name: "load", typeName: "Payload", kind: .methodReturn)))
    }

    func testTypeAttributesDoNotEmitPayloadIdentifiers() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Attributes.swift"),
            path: "Attributes.swift",
            contents: "struct CallbackHolder { let callback: @convention(c) () -> Void }"
        )

        let holder = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false).first)

        XCTAssertTrue(holder.members.contains(SwiftMember(name: "callback", typeName: "Void", kind: .property)))
        XCTAssertFalse(holder.members.contains { $0.typeName == "c" || $0.typeName == "convention" })
        XCTAssertFalse(holder.members.contains { $0.typeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testSingleArbitraryClassClauseIsClassifiedAsConformance() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Navigator.swift"),
            path: "Navigator.swift",
            contents: "final class Navigator: Routable {}"
        )

        let navigator = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false).first)

        XCTAssertEqual(navigator.inheritedTypes, [])
        XCTAssertEqual(navigator.conformances, ["Routable"])
    }

    func testStringLiteralParenthesesDoNotAffectMethodParameters() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/StringParameters.swift"),
            path: "StringParameters.swift",
            contents: "struct Printer { func render(message: String = \"()\") -> Output { Factory() } }"
        )

        let printer = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: true).first)

        XCTAssertTrue(printer.members.contains(SwiftMember(name: "message", typeName: "String", kind: .methodParameter)))
        XCTAssertTrue(printer.members.contains(SwiftMember(name: "render", typeName: "Output", kind: .methodReturn)))
        XCTAssertTrue(printer.members.contains(SwiftMember(name: "Factory", typeName: "Factory", kind: .bodyReference)))
    }

    func testStringInterpolationBodyReferencesAreParsedWhenEnabled() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Interpolation.swift"),
            path: "Interpolation.swift",
            contents: "struct Renderer { func render() { let message = \"\\(Factory())\" } }"
        )

        let renderer = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: true).first)

        XCTAssertTrue(renderer.members.contains(SwiftMember(name: "Factory", typeName: "Factory", kind: .bodyReference)))
    }

    func testInterpolationWithNestedStringLiteralPreservesBodyReferenceAndMasksLiteralText() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/NestedInterpolation.swift"),
            path: "NestedInterpolation.swift",
            contents: """
            struct Renderer {
                func render() {
                    let message = "\\(Factory(label: \"(\")) struct Phantom { }"
                }
            }
            struct Following {}
            """
        )

        let types = try SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: true)
        let renderer = try XCTUnwrap(types.first { $0.name == "Renderer" })

        XCTAssertEqual(types.map(\.name), ["Renderer", "Following"])
        XCTAssertTrue(renderer.members.contains(SwiftMember(name: "Factory", typeName: "Factory", kind: .bodyReference)))
    }

    func testMultilineStringInterpolationPreservesBodyReference() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/MultilineInterpolation.swift"),
            path: "MultilineInterpolation.swift",
            contents: "struct Renderer { func render() { let message = \"\"\"\n\\(Factory())\n\"\"\" } }"
        )

        let renderer = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: true).first)

        XCTAssertTrue(renderer.members.contains(SwiftMember(name: "Factory", typeName: "Factory", kind: .bodyReference)))
    }

    func testParsesSourceFromParserFixture() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ParserFixture.swift")
        let contents = try String(contentsOf: fixtureURL, encoding: .utf8)
        let file = SwiftSourceFile(url: fixtureURL, path: "Tests/Fixtures/ParserFixture.swift", contents: contents)

        let fixture = try XCTUnwrap(SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false).first)

        XCTAssertEqual(fixture.name, "ParserFixture")
        XCTAssertEqual(fixture.inheritedTypes, ["NSObject"])
        XCTAssertEqual(fixture.conformances, ["FixtureProtocol"])
        XCTAssertTrue(fixture.members.contains(SwiftMember(name: "service", typeName: "FixtureService", kind: .property)))
        XCTAssertTrue(fixture.members.contains(SwiftMember(name: "load", typeName: "FixtureModel", kind: .methodReturn)))
    }

    func testCollectsImportedModuleNamesOnEveryTypeDeclaredInTheFile() throws {
        let file = SwiftSourceFile(
            url: URL(fileURLWithPath: "/tmp/Consumer.swift"),
            path: "Sources/ModuleB/Consumer.swift",
            contents: """
            import Foundation
            import ModuleA

            struct Consumer {
                let config: Config
            }

            struct Helper {}
            """
        )

        let types = try SwiftSyntaxTypeParser().parse(file: file, includeBodyReferences: false)

        XCTAssertEqual(types.map(\.name).sorted(), ["Consumer", "Helper"])
        for type in types {
            XCTAssertEqual(type.imports, ["Foundation", "ModuleA"])
        }
    }
}
