import os

/// Central os.Logger handles, used for genuine failures (errors). Stream with:
///   log stream --predicate 'subsystem == "com.metalbreeze.Nook"'
enum Log {
    private static let subsystem = "com.metalbreeze.Nook"
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let switcher = Logger(subsystem: subsystem, category: "switcher")
    static let activate = Logger(subsystem: subsystem, category: "activate")
}
