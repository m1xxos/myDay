import Foundation
import AVFoundation
import AppKit

public final class TimelapseGenerator: @unchecked Sendable {
    public static let shared = TimelapseGenerator()

    public init() {}

    /// Compiles an array of JPEG frame URLs into a hardware-accelerated H.264 MP4 video.
    public func generateTimelapseVideo(
        frameURLs: [URL],
        outputURL: URL,
        fps: Int32 = 30
    ) async throws -> URL {
        guard !frameURLs.isEmpty else {
            throw NSError(domain: "TimelapseGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No frames provided"])
        }

        // Remove old file if exists
        try? FileManager.default.removeItem(at: outputURL)

        // Load first image to get dimensions
        guard let firstImage = NSImage(contentsOf: frameURLs[0]),
              let firstRep = firstImage.representations.first else {
            throw NSError(domain: "TimelapseGenerator", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to read first frame"])
        }

        let width = Int(firstRep.pixelsWide > 0 ? firstRep.pixelsWide : Int(firstImage.size.width))
        let height = Int(firstRep.pixelsHigh > 0 ? firstRep.pixelsHigh : Int(firstImage.size.height))

        // Ensure even dimensions for H.264
        let videoWidth = width - (width % 2)
        let videoHeight = height - (height % 2)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: videoWidth,
            kCVPixelBufferHeightKey as String: videoHeight,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "TimelapseGenerator", code: -3, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
        }
        writer.add(writerInput)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frameDuration = CMTime(value: 1, timescale: fps)
        var frameIndex: Int64 = 0

        // If only 1 or 2 frames exist, duplicate them so that video writer can create a valid playable clip
        var effectiveURLs = frameURLs
        if effectiveURLs.count == 1 {
            effectiveURLs = Array(repeating: frameURLs[0], count: 15)
        } else if effectiveURLs.count == 2 {
            effectiveURLs = [frameURLs[0], frameURLs[0], frameURLs[1], frameURLs[1]]
        }

        for url in effectiveURLs {
            autoreleasepool {
                guard let nsImage = NSImage(contentsOf: url),
                      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    return
                }

                while !writerInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.005)
                }

                if let pixelBuffer = newPixelBuffer(from: cgImage, width: videoWidth, height: videoHeight) {
                    let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                    adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                    frameIndex += 1
                }
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if let error = writer.error {
            throw error
        }

        return outputURL
    }

    private func newPixelBuffer(
        from image: CGImage,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let pixelData = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )

        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
