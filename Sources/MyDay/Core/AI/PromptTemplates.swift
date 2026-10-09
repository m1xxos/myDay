import Foundation

public struct AIActivityResponse: Codable, Sendable {
    public let title: String
    public let summary: String
    public let category: String
    public let tags: [String]

    public init(title: String, summary: String, category: String, tags: [String]) {
        self.title = title
        self.summary = summary
        self.category = category
        self.tags = tags
    }
}

public enum PromptTemplates {
    public static let systemPrompt = """
    You are an automated minimalist work journal analyzer.
    Your task is to analyze computer activity (active applications, window titles, and on-screen OCR text) and summarize what the user was doing.
    You must respond ONLY with a valid JSON object matching the requested schema. No markdown formatting outside the JSON, no intro, no chit-chat.
    """

    public static func buildUserPrompt(
        timeRangeString: String,
        appUsages: [AppUsageSlice],
        ocrKeywords: [String],
        keyTextLines: [String]
    ) -> String {
        var text = "Time Period: \(timeRangeString)\n\n"

        text += "Applications used:\n"
        for usage in appUsages.sorted(by: { $0.durationSeconds > $1.durationSeconds }) {
            let minutes = max(1, Int(usage.durationSeconds / 60))
            let titles = usage.windowTitles.prefix(3).joined(separator: " | ")
            text += "- \(usage.appName) (\(minutes)m): \(titles.isEmpty ? "Active" : titles)\n"
        }

        if !ocrKeywords.isEmpty {
            text += "\nOn-Screen Keywords (extracted via local OCR):\n"
            text += ocrKeywords.joined(separator: ", ") + "\n"
        }

        if !keyTextLines.isEmpty {
            text += "\nVisible On-Screen Content Excerpt:\n"
            text += keyTextLines.prefix(6).joined(separator: "\n") + "\n"
        }

        text += """

        Output schema (strictly valid JSON):
        {
          "title": "Concise descriptive title of what was done (max 6-8 words, in Russian if user works in Russian or English if in English)",
          "summary": "1-2 brief bullet points or sentences describing the work accomplished (REQUIRED, do not leave empty)",
          "category": "Development | Writing | Research | Communication | Design | Entertainment | Utility | Other",
          "tags": ["tag1", "tag2", "tag3"]
        }
        """

        return text
    }
}
