import Foundation
import AppKit

public final class ObsidianExporter: Sendable {
    public static let shared = ObsidianExporter()

    public init() {}

    /// Generates a comprehensive Obsidian Markdown document for an entire day of cards.
    public func exportDayToMarkdown(date: Date, cards: [TimelineCard]) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateString = df.string(from: date)

        let totalDuration = cards.reduce(0.0) { $0 + $1.duration }
        let totalHours = Int(totalDuration) / 3600
        let totalMinutes = (Int(totalDuration) % 3600) / 60
        let totalTimeString = "\(totalHours)h \(totalMinutes)m"

        // Group categories
        var categoryDurations: [ActivityCategory: TimeInterval] = [:]
        for card in cards {
            categoryDurations[card.category, default: 0] += card.duration
        }

        let sortedCategories = categoryDurations.sorted(by: { $0.value > $1.value })
        let topCategory = sortedCategories.first?.key.rawValue ?? "General"

        // 1. YAML Frontmatter
        var md = """
        ---
        date: \(dateString)
        total_time: "\(totalTimeString)"
        top_category: "\(topCategory)"
        categories:
        """

        for (cat, dur) in sortedCategories {
            let h = Int(dur) / 3600
            let m = (Int(dur) % 3600) / 60
            md += "\n  - \(cat.rawValue): \"\(h)h \(m)m\""
        }

        md += """

        tags:
          - myday
          - daily-log
          - work-journal
        ---

        # 📅 Дневной журнал — \(dateString)

        ## 📊 Сводка дня
        - ⏱️ **Общее активное время:** \(totalTimeString)
        - 🎯 **Основной фокус:** \(topCategory)
        - 📑 **Всего сессий:** \(cards.count)

        ---

        ## ⏱️ Таймлайн активности

        """

        // 2. Timeline cards
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        for card in cards {
            let start = timeFormatter.string(from: card.startTime)
            let end = timeFormatter.string(from: card.endTime)
            let durationMin = max(1, Int(card.duration / 60))

            md += "### \(start) – \(end) · \(card.category.displayName) (\(durationMin) мин)\n"
            md += "> [!info] \(card.title)\n"

            let summaryLines = card.summary.components(separatedBy: "\n")
            for line in summaryLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    md += "> \(trimmed)\n"
                }
            }

            md += ">\n"

            // Apps breakdown
            if !card.appUsages.isEmpty {
                let totalSec = max(1, card.appUsages.reduce(0.0) { $0 + $1.durationSeconds })
                let appsStr = card.appUsages
                    .sorted(by: { $0.durationSeconds > $1.durationSeconds })
                    .map { usage in
                        let pct = Int((usage.durationSeconds / totalSec) * 100)
                        return "\(usage.appName) (\(pct)%)"
                    }
                    .joined(separator: ", ")
                md += "> **Приложения:** \(appsStr)\n"
            }

            // Tags
            if !card.tags.isEmpty {
                let tagStr = card.tags.map { "#\($0.replacingOccurrences(of: " ", with: "_"))" }.joined(separator: " ")
                md += "> **Теги:** \(tagStr)\n"
            }

            md += "\n"
        }

        return md
    }

    /// Generates markdown for a single card.
    public func exportCardToMarkdown(_ card: TimelineCard) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let start = timeFormatter.string(from: card.startTime)
        let end = timeFormatter.string(from: card.endTime)
        let durationMin = max(1, Int(card.duration / 60))

        var md = "### \(start) – \(end) · \(card.category.displayName) (\(durationMin) мин)\n"
        md += "> [!info] \(card.title)\n"
        md += "> \(card.summary)\n>\n"

        if !card.appUsages.isEmpty {
            let totalSec = max(1, card.appUsages.reduce(0.0) { $0 + $1.durationSeconds })
            let appsStr = card.appUsages
                .map { "\(SystemAppIconHelper.cleanName($0.appName)) (\(Int(($0.durationSeconds / totalSec) * 100))%)" }
                .joined(separator: ", ")
            md += "> **Приложения:** \(appsStr)\n"
        }

        if !card.tags.isEmpty {
            let tags = card.tags.map { "#\($0)" }.joined(separator: " ")
            md += "> **Теги:** \(tags)\n"
        }

        return md
    }

    /// Copies text to macOS general clipboard.
    @MainActor
    public func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private enum SystemAppIconHelper {
    static func cleanName(_ name: String) -> String {
        return name.replacingOccurrences(of: ".app", with: "")
    }
}
