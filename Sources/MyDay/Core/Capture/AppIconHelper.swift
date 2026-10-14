import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public enum AppIconHelper {
    private static var iconCache: [String: NSImage] = [:]

    public static func icon(forBundleId bundleId: String, appName: String) -> NSImage {
        let key = bundleId.isEmpty ? appName : bundleId

        if let cached = iconCache[key] {
            return cached
        }

        var iconImage: NSImage?

        // 1. Try URL for bundle identifier
        if !bundleId.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            iconImage = NSWorkspace.shared.icon(forFile: url.path)
        }

        // 2. Try common Application paths
        if iconImage == nil {
            let candidates = [
                "/Applications/\(appName).app",
                "/System/Applications/\(appName).app",
                "/System/Applications/Utilities/\(appName).app"
            ]
            for path in candidates {
                if FileManager.default.fileExists(atPath: path) {
                    iconImage = NSWorkspace.shared.icon(forFile: path)
                    break
                }
            }
        }

        // 3. Fallback generic app icon
        let finalImage = iconImage ?? NSWorkspace.shared.icon(for: UTType.application)

        iconCache[key] = finalImage
        return finalImage
    }
}

public struct AppIconView: View {
    let bundleId: String
    let appName: String
    var size: CGFloat = 16

    public init(bundleId: String = "", appName: String, size: CGFloat = 16) {
        self.bundleId = bundleId
        self.appName = appName
        self.size = size
    }

    public var body: some View {
        let nsImage = AppIconHelper.icon(forBundleId: bundleId, appName: appName)
        Image(nsImage: nsImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}
