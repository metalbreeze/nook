import XCTest
@testable import Nook

final class MRUOrderTests: XCTestCase {
    func test_recencyOrdersKnownPIDsFirst() {
        // recency says 30 used most recently, then 10.
        let result = MRUOrder.ordered([10, 20, 30], byRecency: [30, 10])
        XCTAssertEqual(result, [30, 10, 20]) // 20 unknown -> appended in place
    }

    func test_unknownPIDsKeepRelativeOrderAfterKnown() {
        let result = MRUOrder.ordered([10, 20, 30, 40], byRecency: [40])
        XCTAssertEqual(result, [40, 10, 20, 30])
    }

    func test_emptyRecencyLeavesOrderUnchanged() {
        XCTAssertEqual(MRUOrder.ordered([10, 20, 30], byRecency: []), [10, 20, 30])
    }

    func test_recencyEntriesNotInPIDsAreIgnored() {
        let result = MRUOrder.ordered([10, 20], byRecency: [99, 20, 88, 10])
        XCTAssertEqual(result, [20, 10])
    }

    func test_duplicateRecencyEntriesDoNotDuplicate() {
        let result = MRUOrder.ordered([10, 20], byRecency: [20, 20, 10, 10])
        XCTAssertEqual(result, [20, 10])
    }

    func test_emptyPIDsYieldsEmpty() {
        XCTAssertEqual(MRUOrder.ordered([], byRecency: [10, 20]), [])
    }
}
