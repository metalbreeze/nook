import os
import CoreGraphics

/// Central os.Logger handles. Stream from a terminal with:
///   log stream --level debug --predicate 'subsystem == "com.metalbreeze.Nook"'
/// or filter by category, e.g. category == "activate".
enum Log {
    private static let subsystem = "com.metalbreeze.Nook"
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let switcher = Logger(subsystem: subsystem, category: "switcher")
    static let activate = Logger(subsystem: subsystem, category: "activate")
}

extension CGRect {
    /// Compact "(x,y wxh)" form for log lines.
    var logDesc: String {
        "(\(Int(origin.x)),\(Int(origin.y)) \(Int(size.width))x\(Int(size.height)))"
    }
}
