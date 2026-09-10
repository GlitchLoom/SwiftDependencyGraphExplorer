import Foundation

// Source fixture read by SwiftTypeParserTests to exercise file-backed parser input.
final class ParserFixture: NSObject, FixtureProtocol {
    let service: FixtureService

    init(service: FixtureService) {
        self.service = service
    }

    func load(id: FixtureIdentifier) -> FixtureModel {
        FixtureModel()
    }
}

extension ParserFixture {
    var formatter: DateFormatter { DateFormatter() }
}

struct FixtureModel {}
protocol FixtureProtocol {}
protocol FixtureService {}
struct FixtureIdentifier {}
