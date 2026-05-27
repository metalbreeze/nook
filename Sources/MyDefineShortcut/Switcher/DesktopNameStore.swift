import Foundation

/// Persists per-Space desktop names in UserDefaults. Falls back to "Desktop"
/// when a Space has no name. Keyed by the Space ID (as a String).
struct DesktopNameStore {
    static let defaultName = "Desktop"

    private let defaults: UserDefaults
    private let key = "desktopNames"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func name(for spaceID: UInt64) -> String {
        storedName(for: spaceID) ?? Self.defaultName
    }

    func storedName(for spaceID: UInt64) -> String? {
        let map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        return map[String(spaceID)]
    }

    func setName(_ name: String, for spaceID: UInt64) {
        var map = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            map[String(spaceID)] = nil
        } else {
            map[String(spaceID)] = trimmed
        }
        defaults.set(map, forKey: key)
    }
}
