import AppKit
import CoreServices

// MARK: - SkyLight (private) window-focus SPI
//
// Focusing a window by its CGWindowID through SkyLight is the only mechanism
// that reliably brings a window forward *and* lets macOS perform its own
// animated Space switch to that window's desktop — exactly what the OS does
// when you Cmd+Tab to an app whose front window lives on another Space.
//
// This works regardless of Accessibility visibility: kAXWindowsAttribute only
// lists windows on the active Space, and CGSManagedDisplaySetCurrentSpace only
// updates CGS bookkeeping without driving the visual switch. Neither can move
// to an off-Space window; this can.
//
// The two SLPS functions live in the private SkyLight framework, which is not
// link-time visible (CoreGraphics re-exports the CGS* symbols but not these),
// so we resolve them at runtime via dlsym from the already-loaded image.

private let kCPSUserGenerated: UInt32 = 0x200

private typealias SetFrontFn =
    @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
private typealias PostEventFn =
    @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafePointer<UInt8>) -> CGError

@_silgen_name("GetProcessForPID")
private func GetProcessForPID(_ pid: pid_t,
                              _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

private let skylightHandle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

private let setFrontProcess: SetFrontFn? =
    dlsym(skylightHandle, "_SLPSSetFrontProcessWithOptions").map { unsafeBitCast($0, to: SetFrontFn.self) }

private let postEventRecord: PostEventFn? =
    dlsym(skylightHandle, "SLPSPostEventRecordTo").map { unsafeBitCast($0, to: PostEventFn.self) }

enum WindowFocus {
    /// Brings the window with `windowID` (owned by `pid`) to the front, switching
    /// Spaces if it lives on another desktop. Falls back to `WindowActivator`
    /// (AX-raise) when SkyLight is unavailable or the PSN can't be resolved.
    static func focus(windowID: CGWindowID, info: WindowInfo, pid: pid_t) {
        var psn = ProcessSerialNumber()
        guard windowID != kCGNullWindowID,
              GetProcessForPID(pid, &psn) == noErr,
              let setFront = setFrontProcess,
              let postEvent = postEventRecord else {
            Log.activate.notice("WindowFocus: SkyLight/PSN unavailable for pid=\(pid, privacy: .public) — AX fallback")
            WindowActivator.activate(info, pid: pid)
            return
        }
        Log.activate.notice("WindowFocus.focus id=\(windowID, privacy: .public) pid=\(pid, privacy: .public)")
        // Make the owning process frontmost, tied to this specific window.
        _ = setFront(&psn, windowID, kCPSUserGenerated)
        // Synthesize the two SkyLight events that raise + key the window.
        makeKeyWindow(postEvent, &psn, windowID)
    }

    /// Posts the two crafted SkyLight event records that raise the window and
    /// make it key. Byte layout matches the long-standing SkyLight ABI used by
    /// other window managers.
    private static func makeKeyWindow(_ postEvent: PostEventFn,
                                      _ psn: inout ProcessSerialNumber,
                                      _ windowID: CGWindowID) {
        func post(_ eighthByte: UInt8) {
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x08] = eighthByte
            bytes[0x3a] = 0x10
            var wid = windowID
            withUnsafeBytes(of: &wid) { raw in
                for i in 0..<MemoryLayout<CGWindowID>.size { bytes[0x3c + i] = raw[i] }
            }
            for i in 0..<0x10 { bytes[0x20 + i] = 0xff }
            _ = postEvent(&psn, &bytes)
        }
        post(0x01)
        post(0x02)
    }
}
