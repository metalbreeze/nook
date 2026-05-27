import ScreenCaptureKit
import CoreGraphics

enum ThumbnailCapturer {
    static func capture(_ window: SCWindow, maxWidth: CGFloat = 640) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = max(1, window.frame.width / maxWidth)
        config.width = max(1, Int(window.frame.width / scale))
        config.height = max(1, Int(window.frame.height / scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
