import Foundation

// MARK: - Activity Category

public enum ActivityCategory: String, Codable, CaseIterable, Sendable {
    case work = "Work"
    case development = "Development"
    case writing = "Writing"
    case research = "Research"
    case communication = "Communication"
    case design = "Design"
    case entertainment = "Entertainment"
    case utility = "Utility"
    case other = "Other"

    public var displayName: String {
        switch self {
        case .work: return "Работа"
        case .development: return "Разработка"
        case .writing: return "Тексты / Документы"
        case .research: return "Исследования / Браузер"
        case .communication: return "Общение"
        case .design: return "Дизайн"
        case .entertainment: return "Медиа / Отдых"
        case .utility: return "Система"
        case .other: return "Другое"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .work: return "briefcase.fill"
        case .development: return "hammer.fill"
        case .writing: return "pencil.line"
        case .research: return "safari.fill"
        case .communication: return "message.fill"
        case .design: return "paintpalette.fill"
        case .entertainment: return "play.tv.fill"
        case .utility: return "gearshape.fill"
        case .other: return "sparkles"
        }
    }

    public var colorHex: String {
        switch self {
        case .work: return "#2979FF"        // Electric / Work Blue
        case .development: return "#4A90E2" // Crisp Blue
        case .writing: return "#7E57C2"     // Deep Lavender
        case .research: return "#26A69A"    // Teal
        case .communication: return "#5C6BC0" // Indigo
        case .design: return "#EC407A"      // Soft Rose
        case .entertainment: return "#FF7043" // Coral
        case .utility: return "#78909C"     // Slate Gray
        case .other: return "#8D6E63"       // Muted Umber
        }
    }

    public static func match(from string: String, ocrKeywords: [String] = []) -> ActivityCategory {
        let lowered = string.lowercased()

        // 1. Direct string match
        if lowered.contains("work") || lowered.contains("работ") || lowered.contains("job") {
            return .work
        } else if lowered.contains("dev") || lowered.contains("code") || lowered.contains("разработ") || lowered.contains("program") || lowered.contains("xcode") || lowered.contains("terminal") || lowered.contains("warp") || lowered.contains("studio") {
            return .development
        } else if lowered.contains("writ") || lowered.contains("text") || lowered.contains("документ") || lowered.contains("note") || lowered.contains("obsidian") || lowered.contains("notion") {
            return .writing
        } else if lowered.contains("research") || lowered.contains("brows") || lowered.contains("исслед") || lowered.contains("search") || lowered.contains("safari") || lowered.contains("chrome") || lowered.contains("arc") || lowered.contains("firefox") || lowered.contains("zen") {
            return .research
        } else if lowered.contains("commun") || lowered.contains("chat") || lowered.contains("сообщ") || lowered.contains("slack") || lowered.contains("telegram") || lowered.contains("vk") || lowered.contains("mail") {
            return .communication
        } else if lowered.contains("design") || lowered.contains("figma") || lowered.contains("дизайн") {
            return .design
        } else if lowered.contains("entertain") || lowered.contains("video") || lowered.contains("youtube") || lowered.contains("game") {
            return .entertainment
        } else if lowered.contains("util") || lowered.contains("system") || lowered.contains("систем") {
            return .utility
        }

        // 2. If app or title is remote desktop or generic, inspect on-screen OCR keywords
        if !ocrKeywords.isEmpty {
            let joinedOCR = ocrKeywords.joined(separator: " ").lowercased()
            if joinedOCR.contains("code") || joinedOCR.contains("sql") || joinedOCR.contains("api") || joinedOCR.contains("git") || joinedOCR.contains("dev") || joinedOCR.contains("func") || joinedOCR.contains("class") || joinedOCR.contains("build") || joinedOCR.contains("error") || joinedOCR.contains("debug") || joinedOCR.contains("studio") {
                return .development
            }
            if joinedOCR.contains("server") || joinedOCR.contains("admin") || joinedOCR.contains("сервер") || joinedOCR.contains("терминал") || joinedOCR.contains("cmd") || joinedOCR.contains("powershell") || joinedOCR.contains("ssh") || joinedOCR.contains("devops") || joinedOCR.contains("kesl") || joinedOCR.contains("naumen") {
                return .work
            }
            if joinedOCR.contains("doc") || joinedOCR.contains("excel") || joinedOCR.contains("отчет") || joinedOCR.contains("таблиц") || joinedOCR.contains("документ") || joinedOCR.contains("word") {
                return .writing
            }
            if joinedOCR.contains("call") || joinedOCR.contains("видеозвонок") || joinedOCR.contains("звонки") || joinedOCR.contains("чат") || joinedOCR.contains("клиенты") {
                return .communication
            }
        }

        // Remote desktop default is ALWAYS Work (or Development) — NEVER Utility / System!
        if lowered.contains("windows app") || lowered.contains("remote desktop") || lowered.contains("rdp") || lowered.contains("wab2") {
            return .work
        }

        return .other
    }
}

// MARK: - App Usage Slice

public struct AppUsageSlice: Codable, Identifiable, Sendable {
    public var id: String { appName }
    public let appName: String
    public let bundleId: String
    public var durationSeconds: TimeInterval
    public var windowTitles: [String]

    public init(appName: String, bundleId: String, durationSeconds: TimeInterval, windowTitles: [String] = []) {
        self.appName = appName
        self.bundleId = bundleId
        self.durationSeconds = durationSeconds
        self.windowTitles = windowTitles
    }
}

// MARK: - Timeline Card

public struct TimelineCard: Codable, Identifiable, Sendable {
    public let id: UUID
    public let startTime: Date
    public var endTime: Date
    public var title: String
    public var summary: String
    public var category: ActivityCategory
    public var tags: [String]
    public var appUsages: [AppUsageSlice]
    public var keyframePath: String?
    public var timelapseVideoPath: String?
    public var frameCount: Int
    public var isAIAnalyzed: Bool
    public var ocrKeywords: [String]

    public var duration: TimeInterval {
        max(1, endTime.timeIntervalSince(startTime))
    }

    public var durationFormatted: String {
        let m = max(1, Int(duration) / 60)
        if m >= 60 {
            return "\(m / 60)ч \(m % 60)м"
        } else {
            return "\(m) мин"
        }
    }

    public var primaryApp: String {
        appUsages.max(by: { $0.durationSeconds < $1.durationSeconds })?.appName ?? "Mac"
    }

    public var cleanedTags: [String] {
        tags.compactMap { tag -> String? in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "#", with: "")
            guard trimmed.count >= 2 && trimmed.count <= 18 else { return nil }
            guard !trimmed.contains("/") && !trimmed.contains("\\") else { return nil }
            return trimmed
        }
    }

    public static func cleanWindowTitle(_ raw: String, appName: String) -> String {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.lowercased() != appName.lowercased() else { return "" }
        
        // Strip email addresses
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"#
        clean = clean.replacingOccurrences(of: emailPattern, with: "", options: .regularExpression)
        
        // Strip noisy browser suffixes
        let suffixes = [
            " - Google Chrome", " - Zen Browser", " - Safari", " - Arc",
            " - Firefox", " - Brave", " - Opera", " | Zen", " — Mozilla Firefox"
        ]
        for s in suffixes {
            if clean.hasSuffix(s) {
                clean = String(clean.dropLast(s.count))
            }
        }
        
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: " -|·\n\t,"))
        return clean
    }

    public init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date,
        title: String,
        summary: String,
        category: ActivityCategory = .other,
        tags: [String] = [],
        appUsages: [AppUsageSlice] = [],
        keyframePath: String? = nil,
        timelapseVideoPath: String? = nil,
        frameCount: Int = 0,
        isAIAnalyzed: Bool = false,
        ocrKeywords: [String] = []
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.summary = summary
        self.category = category
        self.tags = tags
        self.appUsages = appUsages
        self.keyframePath = keyframePath
        self.timelapseVideoPath = timelapseVideoPath
        self.frameCount = frameCount
        self.isAIAnalyzed = isAIAnalyzed
        self.ocrKeywords = ocrKeywords
    }
}

// MARK: - Recorded Frame Metadata

public struct RecordedFrame: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let filePath: String
    public let appName: String
    public let windowTitle: String
    public let diffScore: Float
    public let isKeyframe: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        filePath: String,
        appName: String,
        windowTitle: String,
        diffScore: Float = 0.0,
        isKeyframe: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.filePath = filePath
        self.appName = appName
        self.windowTitle = windowTitle
        self.diffScore = diffScore
        self.isKeyframe = isKeyframe
    }
}

// MARK: - Engine Mode

public enum EngineMode: String, Codable, CaseIterable, Sendable {
    case native = "Native"       // ⚡️ Нативный режим (Без ИИ)
    case lmStudio = "LMStudio"   // 🤖 С локальным ИИ (LM Studio)

    public var displayName: String {
        switch self {
        case .native: return "Нативный (Без ИИ)"
        case .lmStudio: return "Локальный ИИ (LM Studio)"
        }
    }

    public var localizedDescription: String {
        switch self {
        case .native:
            return "Работает автономно: встроенный Apple Vision OCR + эвристики окон macOS. Мгновенная скорость (0 мс), 0 МБ VRAM, 0% расхода батареи."
        case .lmStudio:
            return "Использует локальную языковую модель из LM Studio для генерации детальных текстовых описаний и задач."
        }
    }
}

// MARK: - Analysis Mode

public enum AnalysisMode: String, Codable, CaseIterable, Sendable {
    case textFirst = "Text-First (Apple Neural Engine OCR)"
    case visionAssisted = "Vision-Assisted (1 Downscaled Keyframe)"

    public var localizedDescription: String {
        switch self {
        case .textFirst:
            return "Быстрый режим: использует Apple OCR на чипе M-серии. В LM Studio отправляется только компактный текст (~1 сек ответ, 0 перегрузки VRAM)."
        case .visionAssisted:
            return "Гибридный режим: отправляет 1 сжатый ключевой кадр (768px) вместе с контекстом для более наглядного анализа VLM-моделью."
        }
    }
}

// MARK: - User Settings

public struct UserSettings: Codable, Sendable {
    public var engineMode: EngineMode
    public var lmStudioEndpoint: String
    public var selectedModel: String
    public var analysisMode: AnalysisMode
    public var captureIntervalSeconds: Double
    public var batchDurationMinutes: Int
    public var idleTimeoutSeconds: Double
    public var diffThresholdPercent: Double
    public var retentionDays: Int
    public var autoAnalyze: Bool
    public var excludePrivateBrowsing: Bool

    public init(
        engineMode: EngineMode = .native,
        lmStudioEndpoint: String = "http://127.0.0.1:1234/v1",
        selectedModel: String = "qwen3-vl-4b-instruct",
        analysisMode: AnalysisMode = .textFirst,
        captureIntervalSeconds: Double = 20.0,
        batchDurationMinutes: Int = 10,
        idleTimeoutSeconds: Double = 120.0,
        diffThresholdPercent: Double = 2.5,
        retentionDays: Int = 7,
        autoAnalyze: Bool = true,
        excludePrivateBrowsing: Bool = true
    ) {
        self.engineMode = engineMode
        self.lmStudioEndpoint = lmStudioEndpoint
        self.selectedModel = selectedModel
        self.analysisMode = analysisMode
        self.captureIntervalSeconds = captureIntervalSeconds
        self.batchDurationMinutes = batchDurationMinutes
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.diffThresholdPercent = diffThresholdPercent
        self.retentionDays = retentionDays
        self.autoAnalyze = autoAnalyze
        self.excludePrivateBrowsing = excludePrivateBrowsing
    }

    public static let `default` = UserSettings()

    enum CodingKeys: String, CodingKey {
        case engineMode
        case lmStudioEndpoint
        case selectedModel
        case analysisMode
        case captureIntervalSeconds
        case batchDurationMinutes
        case idleTimeoutSeconds
        case diffThresholdPercent
        case retentionDays
        case autoAnalyze
        case excludePrivateBrowsing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engineMode = try container.decodeIfPresent(EngineMode.self, forKey: .engineMode) ?? .native
        lmStudioEndpoint = try container.decodeIfPresent(String.self, forKey: .lmStudioEndpoint) ?? "http://127.0.0.1:1234/v1"
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? "qwen3-vl-4b-instruct"
        analysisMode = try container.decodeIfPresent(AnalysisMode.self, forKey: .analysisMode) ?? .textFirst
        captureIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .captureIntervalSeconds) ?? 20.0
        batchDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .batchDurationMinutes) ?? 10
        idleTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .idleTimeoutSeconds) ?? 120.0
        diffThresholdPercent = try container.decodeIfPresent(Double.self, forKey: .diffThresholdPercent) ?? 2.5
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 7
        autoAnalyze = try container.decodeIfPresent(Bool.self, forKey: .autoAnalyze) ?? true
        excludePrivateBrowsing = try container.decodeIfPresent(Bool.self, forKey: .excludePrivateBrowsing) ?? true
    }
}

// MARK: - Unfinished Tasks

public struct UnfinishedTask: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var appName: String
    public var category: ActivityCategory
    public var isCompleted: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        appName: String,
        category: ActivityCategory = .other,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.appName = appName
        self.category = category
        self.isCompleted = isCompleted
    }
}

