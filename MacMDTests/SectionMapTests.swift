import XCTest
@testable import MacMD

final class SectionMapTests: XCTestCase {

    func testNoHeadingsDefaultsToLevelOne() {
        let map = SectionMap(headings: [])
        XCTAssertEqual(map.governingLevel(at: 0), 1)
        XCTAssertEqual(map.governingLevel(at: 100), 1)
    }

    func testMarkerBeforeAnyHeadingGetsLevelOne() {
        // A heading begins at location 50; a marker at location 10 precedes it.
        let map = SectionMap(headings: [(location: 50, level: 2)])
        XCTAssertEqual(map.governingLevel(at: 10), 1)
    }

    func testMarkerUnderHeadingTakesThatLevel() {
        let map = SectionMap(headings: [
            (location: 0, level: 1),
            (location: 20, level: 2),
            (location: 40, level: 3),
        ])
        XCTAssertEqual(map.governingLevel(at: 5), 1)
        XCTAssertEqual(map.governingLevel(at: 25), 2)
        XCTAssertEqual(map.governingLevel(at: 45), 3)
        XCTAssertEqual(map.governingLevel(at: 1000), 3)
    }

    func testUnsortedHeadingsAreHandled() {
        let map = SectionMap(headings: [
            (location: 40, level: 3),
            (location: 0, level: 1),
            (location: 20, level: 2),
        ])
        XCTAssertEqual(map.governingLevel(at: 25), 2)
    }

    func testH4HeadingGovernsAtItsOwnLevel() {
        // H4-H6 color inheritance is resolved later via slotIndex; the section
        // map reports the literal heading level it found.
        let map = SectionMap(headings: [(location: 0, level: 4)])
        XCTAssertEqual(map.governingLevel(at: 10), 4)
    }
}
