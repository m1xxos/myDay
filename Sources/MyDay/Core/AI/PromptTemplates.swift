import Foundation

public struct AIActivityResponse: Codable, Sendable {
    public let is_continuation: Bool
    public let title: String
    public let summary: String
    public let category: String
    public let tags: [String]

    public init(is_continuation: Bool, title: String, summary: String, category: String, tags: [String]) {
        self.is_continuation = is_continuation
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
        keyTextLines: [String],
        previousContext: (title: String, summary: String)? = nil
    ) -> String {
        var text = "Time Period: \(timeRangeString)\n\n"

        if let prev = previousContext {
            text += "PREVIOUS ADJACENT ACTIVITY:\n"
            text += "Title: \(prev.title)\nSummary: \(prev.summary)\n\n"
            text += "IMPORTANT: If the user is still doing the same activity or working in the same project/stream/app as PREVIOUS ADJACENT ACTIVITY, set 'is_continuation': true and reuse the same or similar title.\n\n"
        }

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
          "is_continuation": false, // boolean: true if continuing previous activity, false if starting a new distinct task
          "title": "Concise descriptive title of what was done (max 6-8 words, in Russian if user works in Russian or English if in English)",
          "summary": "1-2 brief bullet points or sentences describing the work accomplished (REQUIRED, do not leave empty)",
          "category": "Development | Writing | Research | Communication | Design | Entertainment | Utility | Other",
          "tags": ["tag1", "tag2", "tag3"]
        }
        """

        return text
    }

    public static func buildDaySummaryPrompt(cards: [TimelineCard]) -> String {
        var text = "You are a helpful assistant writing an end-of-day summary. The user worked on the following activities today:\n\n"
        for (i, card) in cards.enumerated() {
            text += "\(i+1). [\(card.category.displayName)] \(card.title)\n"
            if !card.summary.isEmpty {
                text += "   - \(card.summary)\n"
            }
        }
        text += """

        Write a cohesive, structured 2-3 paragraph markdown summary of how the day went, highlighting major focuses, completed tasks, and general themes.
        Keep it concise, friendly, and in the language the user mostly used in the titles (likely Russian).

        Output schema (strictly valid JSON):
        {
          "is_continuation": false,
          "title": "Итоги дня",
          "summary": "Your beautiful markdown text summary goes here. Use \\n for newlines.",
          "category": "Other",
          "tags": ["summary"]
        }
        """
        return text
    }
}
