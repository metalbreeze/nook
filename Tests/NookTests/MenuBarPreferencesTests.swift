import XCTest
@testable import Nook

final class MenuBarPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.menuBarPrefs"

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

    func test_defaultsToTrue() {
        let prefs = MenuBarPreferences(defaults: defaults)
        XCTAssertTrue(prefs.showDesktopName)
    }

    func test_setFalseThenGet() {
        let prefs = MenuBarPreferences(defaults: defaults)
        prefs.showDesktopName = false
        XCTAssertFalse(prefs.showDesktopName)
    }

    func test_setTrueAfterFalse() {
        let prefs = MenuBarPreferences(defaults: defaults)
        prefs.showDesktopName = false
        prefs.showDesktopName = true
        XCTAssertTrue(prefs.showDesktopName)
    }
}
