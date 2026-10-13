import Foundation
import AppKit
import CoreGraphics

public struct WindowContext: Sendable {
    public let appName: String
    public let bundleId: String
    public let windowTitle: String
    public let timestamp: Date
    public let isPrivateBrowsing: Bool

    public init(
        appName: String,
        bundleId: String,
        windowTitle: String,
        timestamp: Date = Date(),
        isPrivateBrowsing: Bool = false
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.timestamp = timestamp
        self.isPrivateBrowsing = isPrivateBrowsing
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
        let isPrivate = isPrivateBrowsing(appName: appName, bundleId: bundleId, windowTitle: windowTitle)

        return WindowContext(
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            isPrivateBrowsing: isPrivate
        )
    }

    public func isSystemLockOrScreensaver(context: WindowContext) -> Bool {
        let lockIdentifiers = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "com.apple.LockScreen"]
        let lockNames = ["loginwindow", "ScreenSaverEngine", "LockScreen"]
        return lockIdentifiers.contains(context.bundleId) || lockNames.contains(context.appName)
    }

    public func isPrivateBrowsing(context: WindowContext) -> Bool {
        if context.isPrivateBrowsing { return true }
        return isPrivateBrowsing(appName: context.appName, bundleId: context.bundleId, windowTitle: context.windowTitle)
    }

    public func isPrivateBrowsing(appName: String, bundleId: String, windowTitle: String) -> Bool {
        let lowerBundle = bundleId.lowercased()
        let lowerApp = appName.lowercased()

        // 1. Tor Browser is 100% private by definition
        if lowerBundle.contains("torbrowser") || lowerBundle.contains("org.torproject") || lowerApp.contains("tor browser") || lowerApp == "tor" {
            return true
        }

        // 2. Browser identification check
        let knownBrowserBundles: Set<String> = [
            "app.zen-browser.zen", "org.mozilla.com.zen.browser", "io.github.zen_browser.zen",
            "com.google.chrome", "com.google.chrome.canary", "com.google.chrome.beta", "com.google.chrome.dev",
            "org.chromium.chromium", "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
            "org.mozilla.nightly", "com.apple.safari", "com.apple.safaritechnologypreview",
            "com.brave.browser", "com.brave.browser.beta", "com.brave.browser.nightly",
            "company.thebrowser.browser", "com.microsoft.edgemac", "com.microsoft.edgemac.canary",
            "com.operasoftware.opera", "com.operasoftware.operagx", "com.vivaldi.vivaldi",
            "org.torproject.torbrowser", "com.duckduckgo.macos.browser", "com.kagi.kagimacos",
            "ru.yandex.desktop.yandex-browser", "com.pushplaylabs.sidekick", "com.sigmaos.sigmaos.macos",
            "net.waterfox.waterfox", "io.gitlab.librewolf-community.librewolf", "one.ablaze.floorp"
        ]

        let isBrowser = knownBrowserBundles.contains(lowerBundle) ||
            lowerBundle.contains("browser") || lowerBundle.contains("firefox") ||
            lowerBundle.contains("chrome") || lowerBundle.contains("safari") ||
            lowerBundle.contains("opera") || lowerBundle.contains("edge") ||
            lowerApp.contains("zen") || lowerApp.contains("safari") ||
            lowerApp.contains("chrome") || lowerApp.contains("firefox") ||
            lowerApp.contains("brave") || lowerApp.contains("arc") ||
            lowerApp.contains("edge") || lowerApp.contains("opera") ||
            lowerApp.contains("vivaldi") || lowerApp.contains("duckduckgo") ||
            lowerApp.contains("yandex")

        guard isBrowser else { return false }

        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 3. Parenthesized indicators (e.g. Zen/Firefox/Chrome/Brave window markers)
        let parenthesizedIndicators = [
            "(private browsing)", "(приватный просмотр)", "(приватное окно)",
            "(private window)", "(private)", "(incognito)", "(инкогнито)",
            "(inprivate)", "(inprivate-просмотр)", "(tor)", "(privater modus)",
            "(navigation privée)", "(navegación privada)", "(navigazione anonima)",
            "(приватний перегляд)", "(частный доступ)", "(са생활 보호)",
            "(プライベートブラウズ)", "(プライベートブラウジング)", "(无痕浏览)",
            "(無痕瀏覽)", "(隐私浏览)"
        ]
        for ind in parenthesizedIndicators {
            if lower.contains(ind) { return true }
        }

        // 4. Suffix indicators (e.g. "YouTube — Zen (Приватный просмотр)", "Google — Инкогнито")
        let suffixIndicators = [
            "- incognito", "— incognito", "- инкогнито", "— инкогнито",
            "- inprivate", "— inprivate", "- inprivate-просмотр", "— inprivate-просмотр",
            "- private", "— private", "- private browsing", "— private browsing",
            "- приватный просмотр", "— приватный просмотр", "- приватное окно",
            "— приватное окно", "- частный доступ", "— частный доступ",
            "| private window", "— tor", "- tor"
        ]
        for suff in suffixIndicators {
            if lower.hasSuffix(suff) { return true }
        }

        // 5. Standalone or start page exact matches
        let standaloneExact: Set<String> = [
            "incognito", "инкогнито", "private browsing", "приватный просмотр",
            "приватное окно", "частный доступ", "private window", "inprivate",
            "inprivate-просмотр", "new incognito tab", "новая вкладка в режиме инкогнито",
            "new private window", "новое приватное окно", "новое частное окно",
            "new private tab", "новая приватная вкладка"
        ]
        if standaloneExact.contains(lower) {
            return true
        }

        return false
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

