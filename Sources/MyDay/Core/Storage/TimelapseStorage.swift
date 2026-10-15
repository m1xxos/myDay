import Foundation
import AppKit

public final class TimelapseStorage: @unchecked Sendable {
    public static let shared = TimelapseStorage()

    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private var baseFramesDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let framesDir = appSupport.appendingPathComponent("MyDay/frames", isDirectory: true)
        if !fileManager.fileExists(atPath: framesDir.path) {
            try? fileManager.createDirectory(at: framesDir, withIntermediateDirectories: true)
        }
        return framesDir
    }

    public func saveFrame(image: CGImage, timestamp: Date = Date(), maxWidth: CGFloat = 1920) -> String? {
        let dayString = dateFormatter.string(from: timestamp)
        let dayDir = baseFramesDirectory.appendingPathComponent(dayString, isDirectory: true)

        if !fileManager.fileExists(atPath: dayDir.path) {
            try? fileManager.createDirectory(at: dayDir, withIntermediateDirectories: true)
        }

        let timeMillis = Int64(timestamp.timeIntervalSince1970 * 1000)
        let fileName = "frame_\(timeMillis).jpg"
        let fileURL = dayDir.appendingPathComponent(fileName)

        // Downscale and compress to JPEG
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let targetSize: NSSize
        if CGFloat(image.width) > maxWidth {
            let scale = maxWidth / CGFloat(image.width)
            targetSize = NSSize(width: maxWidth, height: CGFloat(image.height) * scale)
        } else {
            targetSize = NSSize(width: image.width, height: image.height)
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        nsImage.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else {
            return nil
        }

        do {
            try jpegData.write(to: fileURL)
            return fileURL.path
        } catch {
            print("[TimelapseStorage] Failed to save frame: \(error)")
            return nil
        }
    }

    public func getFrames(for day: Date) -> [URL] {
        let dayString = dateFormatter.string(from: day)
        let dayDir = baseFramesDirectory.appendingPathComponent(dayString, isDirectory: true)

        guard let files = try? fileManager.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: nil) else {
            return []
        }

        return files.filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
    }

    public func getFrames(between start: Date, and end: Date) -> [URL] {
        let calendar = Calendar.current
        var current = start
        var result: [URL] = []

        let startMillis = Int64(start.timeIntervalSince1970 * 1000)
        let endMillis = Int64(end.timeIntervalSince1970 * 1000)

        while current <= end {
            let dayFrames = getFrames(for: current)
            for file in dayFrames {
                let name = file.deletingPathExtension().lastPathComponent
                if name.hasPrefix("frame_"), let millis = Int64(name.replacingOccurrences(of: "frame_", with: "")) {
                    if millis >= startMillis && millis <= endMillis {
                        result.append(file)
                    }
                }
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
        }

        return result.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
    }

    public func cleanOldFrames(retentionDays: Int = 7) {
        guard let dayDirs = try? fileManager.contentsOfDirectory(at: baseFramesDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let cutoffString = dateFormatter.string(from: cutoffDate)

        for dir in dayDirs {
            let folderName = dir.lastPathComponent
            if folderName < cutoffString {
                try? fileManager.removeItem(at: dir)
                print("[TimelapseStorage] Cleaned old frame directory: \(folderName)")
            }
        }
    }
}
