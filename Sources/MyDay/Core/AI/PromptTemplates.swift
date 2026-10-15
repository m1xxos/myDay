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
            let isRDP = WindowTracker.isRemoteDesktopOrVM(appName: usage.appName, bundleId: usage.bundleId)
            let annotation = isRDP ? " [УДАЛЕННЫЙ РАБОЧИЙ СТОЛ / REMOTE PC]" : ""
            text += "- \(usage.appName)\(annotation) (\(minutes)m): \(titles.isEmpty ? "Active" : titles)\n"
        }

        if !ocrKeywords.isEmpty {
            text += "\nOn-Screen Keywords (extracted via local OCR from primary workspace):\n"
            text += ocrKeywords.joined(separator: ", ") + "\n"
        }

        if !keyTextLines.isEmpty {
            text += "\nVisible On-Screen Content Excerpt:\n"
            text += keyTextLines.prefix(10).joined(separator: "\n") + "\n"
        }

        let hasRemoteWork = appUsages.contains { WindowTracker.isRemoteDesktopOrVM(appName: $0.appName, bundleId: $0.bundleId) }
        if hasRemoteWork {
            text += """

            ВАЖНЫЕ ИНСТРУКЦИИ ДЛЯ УДАЛЕННЫХ СТОЛОВ (Windows App / RDP):
            - Если пользователь проводит большую часть времени в Windows App (удаленка), заголовок окна в macOS (напр. wab2.bspb.ru) является лишь адресом сервера.
            - Определи реальную деятельность пользователя (разработка, администрирование, работа с документами/данными, задачи) ПО КЛЮЧЕВЫМ СЛОВАМ OCR И ВИДИМОМУ ТЕКСТУ ВНУТРИ УДАЛЕНКИ.
            - НЕ присваивай активность второстепенным фоновым приложениям (мессенджерам вроде VK WorkSpace, Telegram), если основное время проведено в Windows App!

            """
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

    public static func buildUnfinishedTasksPrompt(cards: [TimelineCard]) -> String {
        var text = """
        You are an automated task manager assistant.
        Analyze the user's computer activity for today and identify actionable UNFINISHED tasks (things the user started, researched, drafted, coded, or left in-progress, but didn't conclude).

        CRITICAL REQUIREMENTS:
        - Output strictly 3 to 6 distinct, actionable tasks.
        - Each task title MUST be concise and formatted as a task manager to-do item (4 to 8 words maximum, starting with an action verb, e.g. 'Дописать рефакторинг WindowTracker', 'Завершить заказ на OZON', 'Разобрать входящие в Gmail').
        - Language: Russian.
        - Do NOT write long explanations, narrative, or full sentences. Keep it clean like Todoist or Things.

        Today's activity timeline:

        """

        for (i, card) in cards.enumerated() {
            let appNames = card.appUsages.map { $0.appName }.joined(separator: ", ")
            let topTitles = card.appUsages.flatMap { $0.windowTitles }.prefix(3).joined(separator: " | ")
            text += "\(i+1). [\(card.category.displayName)] \(card.title) (Apps: \(appNames))\n"
            if !topTitles.isEmpty {
                text += "   Windows: \(topTitles)\n"
            }
            if !card.ocrKeywords.isEmpty {
                text += "   Keywords: \(card.ocrKeywords.prefix(6).joined(separator: ", "))\n"
            }
        }

        text += """

        Output schema (strictly valid JSON):
        {
          "tasks": [
            {
              "title": "Concise task title (4-8 words in Russian)",
              "app_name": "App name (e.g. Zen, Xcode, Warp, Obsidian)",
              "category": "Development | Writing | Research | Communication | Design | Entertainment | Utility | Other"
            }
          ]
        }
        """
        return text
    }
}

public struct AIUnfinishedTasksResponse: Codable, Sendable {
    public struct TaskItem: Codable, Sendable {
        public let title: String
        public let app_name: String
        public let category: String
    }
    public let tasks: [TaskItem]

    public init(tasks: [TaskItem]) {
        self.tasks = tasks
    }
}

