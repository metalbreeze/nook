import AppKit
import SwiftUI

/// Hosting view that responds to a click even when its window/app isn't active,
/// so the switcher's window thumbnails are clickable without first activating us.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
