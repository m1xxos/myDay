import Foundation
import CoreGraphics
@preconcurrency import Vision

public final class TextRecognitionService: @unchecked Sendable {
    public static let shared = TextRecognitionService()

    public init() {}

    public struct RecognitionResult: Sendable {
        public let fullText: String
        public let keyLines: [String]
        public let keywords: [String]
    }

    /// Recognizes text from a CGImage using Apple Vision Framework (runs on Apple Neural Engine).
    public func recognizeText(from image: CGImage, maxLines: Int = 15) async -> RecognitionResult {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: RecognitionResult(fullText: "", keyLines: [], keywords: []))
                    return
                }

                var lines: [String] = []
                for observation in observations {
                    if let candidate = observation.topCandidates(1).first {
                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        if text.count > 3 && !Self.isCommonUINoise(text) {
                            lines.append(text)
                        }
                    }
                }

                let keyLines = Array(lines.prefix(maxLines))
                let fullText = keyLines.joined(separator: "\n")
                let keywords = Self.extractKeywords(from: lines)

                continuation.resume(returning: RecognitionResult(
                    fullText: fullText,
                    keyLines: keyLines,
                    keywords: keywords
                ))
            }

            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "ru-RU"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: RecognitionResult(fullText: "", keyLines: [], keywords: []))
                }
            }
        }
    }

    private static func isCommonUINoise(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let noiseList = [
            "file edit view", "window help", "am", "pm", "wifi", "battery",
            "bluetooth", "control center", "spotlight", "finder", "safari file",
            "bookmark", "history", "develop", "tab", "close"
        ]
        return noiseList.contains(where: { lowered.hasPrefix($0) })
    }

    private static func extractKeywords(from lines: [String], maxCount: Int = 12) -> [String] {
        var wordCounts: [String: Int] = [:]
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "that", "this", "from", "have", "are",
            "was", "were", "will", "your", "what", "which", "about", "into",
            "или", "для", "как", "что", "это", "при", "все", "так", "если"
        ]

        for line in lines {
            let tokens = line.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for token in tokens {
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 4 && !stopWords.contains(trimmed.lowercased()) {
                    wordCounts[trimmed, default: 0] += 1
                }
            }
        }

        return wordCounts.sorted(by: { $0.value > $1.value })
            .prefix(maxCount)
            .map { $0.key }
    }
}
