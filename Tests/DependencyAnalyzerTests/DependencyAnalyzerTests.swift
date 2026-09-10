import XCTest
import SDGECore
@testable import DependencyAnalyzer

final class DependencyAnalyzerTests: XCTestCase {
    func testExpandsLocalTypesToRequestedDepthAndLeavesExternalTypesUnexpanded() {
        let a = SwiftType(name: "A", kind: .class, filePath: "A.swift", members: [.init(name: "b", typeName: "B", kind: .property)])
        let b = SwiftType(name: "B", kind: .struct, filePath: "B.swift", members: [.init(name: "c", typeName: "C", kind: .property), .init(name: "url", typeName: "URL", kind: .property)])
        let c = SwiftType(name: "C", kind: .enum, filePath: "C.swift")

        var options = AnalysisOptions.defaults
        options.depth = 2
        options.includeSystemTypes = true

        let graph = DependencyAnalyzer().analyze(rootTypeName: "A", types: [a, b, c], options: options)

        XCTAssertTrue(graph.nodes.contains(.init(name: "A", kind: .class, isExternal: false)))
        XCTAssertTrue(graph.nodes.contains(.init(name: "B", kind: .struct, isExternal: false)))
        XCTAssertTrue(graph.nodes.contains(.init(name: "C", kind: .enum, isExternal: false)))
        XCTAssertTrue(graph.nodes.contains(.init(name: "URL", kind: nil, isExternal: true)))
        XCTAssertTrue(graph.edges.contains(.init(source: "A", target: "B", relationship: .property, isExternal: false, memberName: "b")))
        XCTAssertTrue(graph.edges.contains(.init(source: "B", target: "C", relationship: .property, isExternal: false, memberName: "c")))
        XCTAssertTrue(graph.edges.contains(.init(source: "B", target: "URL", relationship: .property, isExternal: true, memberName: "url")))
    }

    func testFiltersSystemTypesKindsBodyReferencesAndManualPrefixes() {
        let a = SwiftType(name: "A", kind: .class, filePath: "A.swift", members: [
            .init(name: "view", typeName: "UIView", kind: .property),
            .init(name: "proto", typeName: "InternalProtocol", kind: .property),
            .init(name: "noisy", typeName: "RTILabAnalyticsClient", kind: .property),
            .init(name: "body", typeName: "BodyOnly", kind: .bodyReference)
        ])
        let proto = SwiftType(name: "InternalProtocol", kind: .protocol, filePath: "P.swift")
        let body = SwiftType(name: "BodyOnly", kind: .struct, filePath: "Body.swift")

        var options = AnalysisOptions.defaults
        options.includeSystemTypes = false
        options.includeProtocols = false
        options.includeBodyReferences = false
        options.excludedPrefixes = ["RTILabAnalytics"]

        let graph = DependencyAnalyzer().analyze(rootTypeName: "A", types: [a, proto, body], options: options)

        XCTAssertEqual(Set(graph.nodes.map(\.name)), ["A"])
        XCTAssertTrue(graph.edges.isEmpty)
    }

    func testFiltersAllRequiredSystemNamesAndPrefixesWhenSystemTypesAreDisabled() {
        let systemTypeNames = [
            "UIView", "NSURL", "AVPlayer", "CGColor", "CALayer", "CFString", "CIImage", "MTKView",
            "SKScene", "CLLocation", "MKMapView", "SwiftUI", "Combine", "Foundation", "UIKit", "AppKit"
        ]
        let root = SwiftType(
            name: "Root",
            kind: .class,
            filePath: "Root.swift",
            members: systemTypeNames.map { .init(name: $0, typeName: $0, kind: .property) }
        )

        var options = AnalysisOptions.defaults
        options.includeSystemTypes = false
        options.includeThirdPartyTypes = true

        let graph = DependencyAnalyzer().analyze(rootTypeName: "Root", types: [root], options: options)

        XCTAssertEqual(Set(graph.nodes.map(\.name)), ["Root"])
        XCTAssertTrue(graph.edges.isEmpty)
    }

    func testFiltersStandardLibraryBaseProtocolsWhenSystemTypesAreDisabled() {
        let protocolNames = [
            "Equatable", "Hashable", "Comparable", "Identifiable", "Sendable",
            "Codable", "Decodable", "Encodable", "RawRepresentable",
            "CustomStringConvertible", "CaseIterable", "Sequence", "Collection",
            "ExpressibleByStringLiteral", "ObservableObject", "AdditiveArithmetic"
        ]
        let root = SwiftType(
            name: "Root",
            kind: .class,
            filePath: "Root.swift",
            conformances: protocolNames
        )

        var options = AnalysisOptions.defaults
        options.includeSystemTypes = false
        options.includeThirdPartyTypes = true

        let graph = DependencyAnalyzer().analyze(rootTypeName: "Root", types: [root], options: options)

        XCTAssertEqual(Set(graph.nodes.map(\.name)), ["Root"])
        XCTAssertTrue(graph.edges.isEmpty)
    }

    func testThirdPartyToggleControlsExternalMethodParameterDependencies() {
        let root = SwiftType(
            name: "Root",
            kind: .class,
            filePath: "Root.swift",
            members: [.init(name: "client", typeName: "ThirdPartyClient", kind: .methodParameter)]
        )
        var options = AnalysisOptions.defaults
        options.includeThirdPartyTypes = false

        let excluded = DependencyAnalyzer().analyze(rootTypeName: "Root", types: [root], options: options)
        XCTAssertEqual(Set(excluded.nodes.map(\.name)), ["Root"])
        XCTAssertTrue(excluded.edges.isEmpty)

        options.includeThirdPartyTypes = true
        let included = DependencyAnalyzer().analyze(rootTypeName: "Root", types: [root], options: options)

        XCTAssertTrue(included.nodes.contains(.init(name: "ThirdPartyClient", kind: nil, isExternal: true)))
        XCTAssertTrue(included.edges.contains(.init(source: "Root", target: "ThirdPartyClient", relationship: .methodParameter, isExternal: true, memberName: "client")))
    }

    func testUsedByDirectionExpandsIncomingDependenciesToRequestedDepth() {
        let root = SwiftType(name: "Root", kind: .class, filePath: "Root.swift")
        let firstConsumer = SwiftType(name: "FirstConsumer", kind: .struct, filePath: "First.swift", members: [
            .init(name: "root", typeName: "Root", kind: .property)
        ])
        let secondConsumer = SwiftType(name: "SecondConsumer", kind: .struct, filePath: "Second.swift", members: [
            .init(name: "first", typeName: "FirstConsumer", kind: .property)
        ])
        let thirdConsumer = SwiftType(name: "ThirdConsumer", kind: .struct, filePath: "Third.swift", members: [
            .init(name: "second", typeName: "SecondConsumer", kind: .property)
        ])
        let fourthConsumer = SwiftType(name: "FourthConsumer", kind: .struct, filePath: "Fourth.swift", members: [
            .init(name: "third", typeName: "ThirdConsumer", kind: .property)
        ])
        var options = AnalysisOptions.defaults
        options.depth = 3
        options.direction = .usedBy

        let graph = DependencyAnalyzer().analyze(
            rootTypeName: "Root",
            types: [root, firstConsumer, secondConsumer, thirdConsumer, fourthConsumer],
            options: options
        )

        XCTAssertEqual(Set(graph.nodes.map(\.name)), ["Root", "FirstConsumer", "SecondConsumer", "ThirdConsumer"])
        XCTAssertTrue(graph.edges.contains(.init(source: "FirstConsumer", target: "Root", relationship: .property, isExternal: false, memberName: "root")))
        XCTAssertTrue(graph.edges.contains(.init(source: "SecondConsumer", target: "FirstConsumer", relationship: .property, isExternal: false, memberName: "first")))
        XCTAssertTrue(graph.edges.contains(.init(source: "ThirdConsumer", target: "SecondConsumer", relationship: .property, isExternal: false, memberName: "second")))
        XCTAssertFalse(graph.nodes.contains { $0.name == "FourthConsumer" })
    }

    func testBothDirectionIncludesOutgoingAndIncomingDependencies() {
        let root = SwiftType(name: "Root", kind: .class, filePath: "Root.swift", members: [
            .init(name: "service", typeName: "Service", kind: .property)
        ])
        let service = SwiftType(name: "Service", kind: .struct, filePath: "Service.swift")
        let consumer = SwiftType(name: "Consumer", kind: .struct, filePath: "Consumer.swift", members: [
            .init(name: "root", typeName: "Root", kind: .property)
        ])
        var options = AnalysisOptions.defaults
        options.depth = 1
        options.direction = .both

        let graph = DependencyAnalyzer().analyze(
            rootTypeName: "Root",
            types: [root, service, consumer],
            options: options
        )

        XCTAssertEqual(Set(graph.nodes.map(\.name)), ["Root", "Service", "Consumer"])
        XCTAssertTrue(graph.edges.contains(.init(source: "Root", target: "Service", relationship: .property, isExternal: false, memberName: "service")))
        XCTAssertTrue(graph.edges.contains(.init(source: "Consumer", target: "Root", relationship: .property, isExternal: false, memberName: "root")))
    }

    func testLocalClassTargetIsLabeledAsInheritanceWhenParserClassifiesItAsConformance() {
        let child = SwiftType(
            name: "Child",
            kind: .class,
            filePath: "Child.swift",
            conformances: ["Parent"]
        )
        let parent = SwiftType(name: "Parent", kind: .class, filePath: "Parent.swift")

        let graph = DependencyAnalyzer().analyze(
            rootTypeName: "Child",
            types: [child, parent],
            options: .defaults
        )

        XCTAssertTrue(graph.edges.contains(.init(
            source: "Child",
            target: "Parent",
            relationship: .inherits,
            isExternal: false
        )))
        XCTAssertFalse(graph.edges.contains { $0.target == "Parent" && $0.relationship == .conforms })
    }

    func testMultipleLocalProtocolTargetsAreLabeledAsConformances() {
        let service = SwiftType(
            name: "Service",
            kind: .class,
            filePath: "Service.swift",
            inheritedTypes: ["Readable"],
            conformances: ["Writable"]
        )
        let readable = SwiftType(name: "Readable", kind: .protocol, filePath: "Readable.swift")
        let writable = SwiftType(name: "Writable", kind: .protocol, filePath: "Writable.swift")

        let graph = DependencyAnalyzer().analyze(
            rootTypeName: "Service",
            types: [service, readable, writable],
            options: .defaults
        )

        XCTAssertTrue(graph.edges.contains(.init(
            source: "Service",
            target: "Readable",
            relationship: .conforms,
            isExternal: false
        )))
        XCTAssertTrue(graph.edges.contains(.init(
            source: "Service",
            target: "Writable",
            relationship: .conforms,
            isExternal: false
        )))
        XCTAssertFalse(graph.edges.contains { $0.relationship == .inherits })
    }

    func testCapturesTheIntroducingMemberNameForFunctionReturnsAndOmitsItForBodyReferencesAndInheritance() {
        let root = SwiftType(
            name: "Root",
            kind: .class,
            filePath: "Root.swift",
            inheritedTypes: ["BaseClass"],
            members: [
                .init(name: "fetchUser", typeName: "User", kind: .methodReturn),
                .init(name: "Logger", typeName: "Logger", kind: .bodyReference)
            ]
        )
        let baseClass = SwiftType(name: "BaseClass", kind: .class, filePath: "BaseClass.swift")

        var options = AnalysisOptions.defaults
        options.includeBodyReferences = true

        let graph = DependencyAnalyzer().analyze(rootTypeName: "Root", types: [root, baseClass], options: options)

        XCTAssertTrue(graph.edges.contains(.init(source: "Root", target: "User", relationship: .methodReturn, isExternal: true, memberName: "fetchUser")))
        XCTAssertTrue(graph.edges.contains(.init(source: "Root", target: "Logger", relationship: .bodyReference, isExternal: true, memberName: nil)))
        XCTAssertTrue(graph.edges.contains(.init(source: "Root", target: "BaseClass", relationship: .inherits, isExternal: false, memberName: nil)))
    }
}
