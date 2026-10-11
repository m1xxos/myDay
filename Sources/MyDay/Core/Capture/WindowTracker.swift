import Foundation
import AppKit
import CoreGraphics

public struct WindowContext: Sendable {
    public let appName: String
    public let bundleId: String
    public let windowTitle: String
    public let timestamp: Date

    public init(appName: String, bundleId: String, windowTitle: String, timestamp: Date = Date()) {
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.timestamp = timestamp
    }
}

public final class WindowTracker: @unchecked Sendable {
    public static let shared = WindowTracker()

    public func getCurrentContext() -> WindowContext {
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "Finder"
        let bundleId = frontApp?.bundleIdentifier ?? "com.apple.finder"
        let pid = frontApp?.processIdentifier ?? 0

        let windowTitle = getActiveWindowTitle(for: pid) ?? appName

        return WindowContext(
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle
        )
    }

    public func isSystemLockOrScreensaver(context: WindowContext) -> Bool {
        let lockIdentifiers = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "com.apple.LockScreen"]
        let lockNames = ["loginwindow", "ScreenSaverEngine", "LockScreen"]
        return lockIdentifiers.contains(context.bundleId) || lockNames.contains(context.appName)
    }

    private func getActiveWindowTitle(for pid: pid_t) -> String? {
        guard pid > 0 else { return nil }

        // 1. Try CGWindowListCopyWindowInfo
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowListInfo {
            if let windowPID = window[kCGWindowOwnerPID as String] as? pid_t, windowPID == pid {
                // Layer 0 is standard application window
                if let layer = window[kCGWindowLayer as String] as? Int, layer == 0 {
                    if let title = window[kCGWindowName as String] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return title
                    }
                }
            }
        }

        return nil
    }
}
