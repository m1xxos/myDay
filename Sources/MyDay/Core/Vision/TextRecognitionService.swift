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
    public func recognizeText(from image: CGImage, maxLines: Int = 30) async -> RecognitionResult {
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ru-RU", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return RecognitionResult(fullText: "", keyLines: [], keywords: [])
            }

            guard let observations = request.results else {
                return RecognitionResult(fullText: "", keyLines: [], keywords: [])
            }

            var lines: [String] = []
            for observation in observations {
                if let candidate = observation.topCandidates(1).first {
                    var text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Strip leading bullet artifacts
                    while text.hasPrefix("•") || text.hasPrefix("·") || text.hasPrefix("-") || text.hasPrefix("*") {
                        text = text.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if text.count >= 3 && !Self.isCommonUINoise(text) {
                        lines.append(text)
                    }
                }
            }

            let keyLines = Array(lines.prefix(maxLines))
            let fullText = keyLines.joined(separator: "\n")
            let keywords = Self.extractKeywords(from: lines)

            return RecognitionResult(
                fullText: fullText,
                keyLines: keyLines,
                keywords: keywords
            )
        }.value
    }

    private static func isCommonUINoise(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let noiseList = [
            "file edit view", "window help", "control center", "spotlight",
            "bookmark", "history", "develop", "close window"
        ]
        return noiseList.contains(where: { lowered.hasPrefix($0) })
    }

    private static func extractKeywords(from lines: [String], maxCount: Int = 18) -> [String] {
        var wordCounts: [String: Int] = [:]
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "that", "this", "from", "have", "are",
            "was", "were", "will", "your", "what", "which", "about", "into", "there",
            "their", "then", "them", "these", "other", "some", "more",
            "или", "для", "как", "что", "это", "при", "все", "так", "если",
            "было", "быть", "когда", "где", "тоже", "только", "после", "через",
            "очень", "своих", "этом", "этой", "того", "этих", "были", "свой"
        ]

        for line in lines {
            let tokens = line.components(separatedBy: CharacterSet.alphanumerics.inverted)
            for token in tokens {
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 3 && !stopWords.contains(trimmed.lowercased()) {
                    // Normalize token casing
                    let displayToken: String
                    if trimmed.uppercased() == trimmed {
                        displayToken = trimmed // e.g. SQL, API, WAB, ERP
                    } else {
                        displayToken = trimmed.prefix(1).uppercased() + trimmed.dropFirst()
                    }
                    wordCounts[displayToken, default: 0] += 1
                }
            }
        }

        return wordCounts.sorted(by: { $0.value > $1.value })
            .prefix(maxCount)
            .map { $0.key }
    }
}
