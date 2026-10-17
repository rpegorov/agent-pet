import AppKit
import CoreGraphics

/// Detects a frontmost application window that covers an entire screen.
enum FullScreenDetector {
    struct Snapshot: Sendable {
        let frontPID: Int32
        let screenFrames: [CGRect]
    }

    private static let tolerance: CGFloat = 1.5
    private static let regularWindowLayer = 0

    /// Captures what must be read on the main thread; nil when no other application is frontmost.
    @MainActor static func snapshot() -> Snapshot? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let primary = NSScreen.screens.first else { return nil }
        let frames = NSScreen.screens.map { cgFrame(of: $0.frame, primaryHeight: primary.frame.height) }
        return Snapshot(frontPID: front.processIdentifier, screenFrames: frames)
    }

    /// Safe to call off the main thread.
    static func isCovering(_ snapshot: Snapshot) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid == snapshot.frontPID,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == regularWindowLayer,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return false }
            return snapshot.screenFrames.contains { matches(bounds, $0) }
        }
    }

    // Quartz window bounds use a top-left origin anchored at the primary screen.
    static func cgFrame(of frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
