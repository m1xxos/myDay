import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

public final class ScreenCaptureManager: @unchecked Sendable {
    public static let shared = ScreenCaptureManager()

    public init() {}

    /// Checks if screen capture permission is granted.
    public func checkPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Requests screen capture permission prompt.
    public func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Captures the main active display as CGImage.
    public func captureMainDisplay(maxWidth: Int = 1440) async -> CGImage? {
        // First try modern ScreenCaptureKit
        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let mainDisplay = content.displays.first else {
                    return fallbackCGDisplayCapture()
                }

                let filter = SCContentFilter(display: mainDisplay, excludingWindows: [])
                let config = SCStreamConfiguration()

                let scale = min(1.0, Double(maxWidth) / Double(mainDisplay.width))
                config.width = Int(Double(mainDisplay.width) * scale)
                config.height = Int(Double(mainDisplay.height) * scale)
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                return image
            } catch {
                // If ScreenCaptureKit fails (e.g. permission or headless), fallback to CGDisplayCreateImage
                return fallbackCGDisplayCapture()
            }
        } else {
            return fallbackCGDisplayCapture()
        }
    }

    private func fallbackCGDisplayCapture() -> CGImage? {
        let displayID = CGMainDisplayID()
        return CGDisplayCreateImage(displayID)
    }
}
