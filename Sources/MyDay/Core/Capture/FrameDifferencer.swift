import Foundation
import CoreGraphics

public final class FrameDifferencer: @unchecked Sendable {
    public static let shared = FrameDifferencer()

    private let sampleWidth = 64
    private let sampleHeight = 64
    private var previousBuffer: [UInt8]?
    private let lock = NSLock()

    public init() {}

    /// Calculates perceptual difference percentage (0.0% to 100.0%) between current and previous frame.
    public func calculateDifference(for image: CGImage) -> (diffPercent: Float, isSignificant: Bool, sampleBuffer: [UInt8]) {
        let currentBuffer = extractGrayscaleThumbnail(from: image)

        lock.lock()
        defer { lock.unlock() }

        guard let prev = previousBuffer, prev.count == currentBuffer.count else {
            self.previousBuffer = currentBuffer
            return (100.0, true, currentBuffer)
        }

        var totalDelta: Int64 = 0
        let count = currentBuffer.count

        for i in 0..<count {
            totalDelta += Int64(abs(Int(currentBuffer[i]) - Int(prev[i])))
        }

        // Max possible delta = count * 255
        let maxDelta = Double(count * 255)
        let diffPercent = Float((Double(totalDelta) / maxDelta) * 100.0)

        // Update previous
        self.previousBuffer = currentBuffer

        return (diffPercent, diffPercent >= 2.5, currentBuffer)
    }

    public func reset() {
        lock.lock()
        previousBuffer = nil
        lock.unlock()
    }

    private func extractGrayscaleThumbnail(from image: CGImage) -> [UInt8] {
        var pixelData = [UInt8](repeating: 0, count: sampleWidth * sampleHeight)
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let context = CGContext(
            data: &pixelData,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return pixelData
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        return pixelData
    }
}
