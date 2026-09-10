import XCTest
@testable import SDGECore

final class SDGECoreTests: XCTestCase {
    func testAnalysisOptionsDefaultDepthIsTwoAndBodyReferencesAreDisabled() {
        let options = AnalysisOptions.defaults

        XCTAssertEqual(options.depth, 2)
        XCTAssertFalse(options.includeBodyReferences)
        XCTAssertTrue(options.includeClasses)
        XCTAssertTrue(options.includeStructs)
        XCTAssertTrue(options.includeEnums)
        XCTAssertTrue(options.includeProtocols)
    }
}
