import XCTest
@testable import Nook

final class DesktopNameStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.desktopNames"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func test_defaultWhenAbsent() {
        let store = DesktopNameStore(defaults: defaults)
        XCTAssertEqual(store.name(for: 1), "Desktop")
    }

    func test_setThenGet() {
        let store = DesktopNameStore(defaults: defaults)
        store.setName("Work", for: 1)
        XCTAssertEqual(store.name(for: 1), "Work")
    }

    func test_perSpaceIndependence() {
        let store = DesktopNameStore(defaults: defaults)
        store.setName("Work", for: 1)
        store.setName("Play", for: 2)
        XCTAssertEqual(store.name(for: 1), "Work")
        XCTAssertEqual(store.name(for: 2), "Play")
    }

    func test_emptyOrWhitespaceNameRemovesEntry() {
        let store = DesktopNameStore(defaults: defaults)
        store.setName("Work", for: 1)
        store.setName("   ", for: 1)
        XCTAssertEqual(store.name(for: 1), "Desktop")
    }

    func test_nameIsTrimmed() {
        let store = DesktopNameStore(defaults: defaults)
        store.setName("  Mail  ", for: 1)
        XCTAssertEqual(store.name(for: 1), "Mail")
    }

    func test_storedName_nilWhenUnset() {
        let store = DesktopNameStore(defaults: defaults)
        XCTAssertNil(store.storedName(for: 1))
    }

    func test_storedName_returnsValueWhenSet() {
        let store = DesktopNameStore(defaults: defaults)
        store.setName("Work", for: 1)
        XCTAssertEqual(store.storedName(for: 1), "Work")
    }
}
