import Foundation

public final class UnfinishedTasksExtractor: @unchecked Sendable {
    public static let shared = UnfinishedTasksExtractor()

    public init() {}

    public func extractTasks(from cards: [TimelineCard]) -> [UnfinishedTask] {
        guard !cards.isEmpty else { return [] }

        var tasks: [UnfinishedTask] = []
        var seenKeys: Set<String> = []

        // Helper to add unique task
        func addTask(title: String, appName: String, category: ActivityCategory) {
            let key = "\(appName):\(title.lowercased())"
            if !seenKeys.contains(key) && tasks.count < 6 {
                seenKeys.insert(key)
                tasks.append(UnfinishedTask(title: title, appName: appName, category: category))
            }
        }

        // 1. Analyze specific window titles across all cards (chronologically latest first)
        let reversedCards = cards.reversed()

        for card in reversedCards {
            for usage in card.appUsages {
                let app = usage.appName
                for rawTitle in usage.windowTitles {
                    let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, title != app else { continue }

                    // A. Email / Inboxes
                    if title.contains("Входящие") || title.contains("Inbox") || title.contains("Gmail") || title.contains("Mail") {
                        if title.contains("(") && title.contains(")") {
                            addTask(title: "Разобрать входящие письма в \(app)", appName: app, category: .communication)
                        } else {
                            addTask(title: "Проверить входящую почту в \(app)", appName: app, category: .communication)
                        }
                    }

                    // B. Messengers (Telegram, Discord, Slack)
                    else if app.contains("Telegram") || app.contains("Discord") || app.contains("Slack") {
                        if title.contains("@") {
                            let parts = title.components(separatedBy: " ")
                            if let atPart = parts.first(where: { $0.starts(with: "@") }) {
                                addTask(title: "Ответить в чате \(atPart)", appName: app, category: .communication)
                            } else {
                                addTask(title: "Ответить на сообщения в \(app)", appName: app, category: .communication)
                            }
                        }
                    }

                    // C. Development / Code / Files / Terminals
                    else if card.category == .development || app == "Xcode" || app == "Warp" || app.contains("Code") || app == "Terminal" {
                        if title.contains(".swift") || title.contains(".py") || title.contains(".ts") || title.contains(".js") || title.contains(".go") || title.contains(".rs") {
                            let file = extractFileName(from: title)
                            addTask(title: "Завершить работу над \(file)", appName: app, category: .development)
                        } else if title.contains("terraform") || title.contains("docker") || title.contains("pi-server") {
                            addTask(title: "Завершить настройку инфраструктуры в \(app)", appName: app, category: .development)
                        } else if title.contains("PR #") || title.contains("Pull Request") || title.contains("Issue") {
                            addTask(title: "Завершить pull request в \(app)", appName: app, category: .development)
                        }
                    }

                    // D. Shopping / Carts
                    else if title.contains("купить на OZON") || title.contains("OZON") || title.contains("Авито") || title.contains("Маркет") {
                        if title.contains("OZON") {
                            addTask(title: "Оформить заказ на OZON", appName: app, category: .utility)
                        } else if title.contains("Авито") {
                            addTask(title: "Проверить объявления на Авито", appName: app, category: .utility)
                        } else {
                            addTask(title: "Завершить оформление покупок в \(app)", appName: app, category: .utility)
                        }
                    }

                    // E. Notes / Obsidian / Writing
                    else if app == "Obsidian" || app == "Notion" || app == "Notes" || card.category == .writing {
                        let cleanNote = TimelineCard.cleanWindowTitle(title, appName: app)
                        if !cleanNote.isEmpty && cleanNote != app {
                            addTask(title: "Дописать заметку «\(cleanNote.prefix(25))»", appName: app, category: .writing)
                        } else {
                            addTask(title: "Завершить запись в \(app)", appName: app, category: .writing)
                        }
                    }

                    // F. Research / Real estate / Study
                    else if title.contains("ЖК ") || title.contains("Квартир") || title.contains("недвижим") {
                        addTask(title: "Сравнить варианты недвижимости", appName: app, category: .research)
                    } else if title.contains("Курс") || title.contains("Практикум") || title.contains("Stepik") {
                        addTask(title: "Продолжить прохождение курса в \(app)", appName: app, category: .research)
                    }
                }
            }
        }

        // 2. If we still need more tasks, synthesize actionable items from recent substantive work cards
        let substantiveCategories: Set<ActivityCategory> = [.development, .writing, .research, .design, .utility]

        for card in reversedCards where substantiveCategories.contains(card.category) {
            if tasks.count >= 5 { break }

            let primaryApp = card.appUsages.max(by: { $0.durationSeconds < $1.durationSeconds })?.appName ?? "Mac"
            let actionTitle = makeActionableTitle(from: card.title, category: card.category, appName: primaryApp)
            addTask(title: actionTitle, appName: primaryApp, category: card.category)
        }

        // Return top tasks (up to 5)
        return Array(tasks.prefix(5))
    }

    private func extractFileName(from title: String) -> String {
        let parts = title.components(separatedBy: CharacterSet(charactersIn: " —-|·/\\"))
        for p in parts {
            let trimmed = p.trimmingCharacters(in: .whitespaces)
            if trimmed.contains(".") && (trimmed.hasSuffix(".swift") || trimmed.hasSuffix(".py") || trimmed.hasSuffix(".ts") || trimmed.hasSuffix(".js") || trimmed.hasSuffix(".yml") || trimmed.hasSuffix(".json")) {
                return trimmed
            }
        }
        return "файлом проекта"
    }

    private func makeActionableTitle(from rawTitle: String, category: ActivityCategory, appName: String) -> String {
        let clean = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip prefixes like "Работа в", "Изучение", "Просмотр"
        let prefixesToReplace: [(prefix: String, action: String)] = [
            ("Работа с кодом", "Завершить работу с кодом"),
            ("Работа в ", "Завершить работу в "),
            ("Работа с ", "Завершить работу с "),
            ("Изучение ", "Продолжить изучение "),
            ("Исследование ", "Продолжить исследование "),
            ("Настройка ", "Закончить настройку "),
            ("Разработка ", "Завершить разработку "),
            ("Создание ", "Завершить создание "),
            ("Написание ", "Дописать ")
        ]

        for p in prefixesToReplace {
            if clean.starts(with: p.prefix) {
                let rest = clean.dropFirst(p.prefix.count)
                return "\(p.action)\(rest)"
            }
        }

        switch category {
        case .development:
            return "Завершить разработку: \(clean)"
        case .writing:
            return "Дописать: \(clean)"
        case .research:
            return "Продолжить изучение: \(clean)"
        case .design:
            return "Доработать дизайн: \(clean)"
        default:
            return "Завершить задачу: \(clean)"
        }
    }
}
