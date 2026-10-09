import Foundation

// MARK: - Activity Category

public enum ActivityCategory: String, Codable, CaseIterable, Sendable {
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

    public static func match(from string: String) -> ActivityCategory {
        let lowered = string.lowercased()
        if lowered.contains("dev") || lowered.contains("code") || lowered.contains("разработ") || lowered.contains("program") {
            return .development
        } else if lowered.contains("writ") || lowered.contains("text") || lowered.contains("документ") || lowered.contains("note") {
            return .writing
        } else if lowered.contains("research") || lowered.contains("brows") || lowered.contains("исслед") || lowered.contains("search") || lowered.contains("safari") || lowered.contains("chrome") || lowered.contains("arc") || lowered.contains("firefox") {
            return .research
        } else if lowered.contains("commun") || lowered.contains("chat") || lowered.contains("сообщ") || lowered.contains("slack") || lowered.contains("telegram") {
            return .communication
        } else if lowered.contains("design") || lowered.contains("figma") || lowered.contains("дизайн") {
            return .design
        } else if lowered.contains("entertain") || lowered.contains("video") || lowered.contains("youtube") || lowered.contains("game") {
            return .entertainment
        } else if lowered.contains("util") || lowered.contains("system") || lowered.contains("систем") {
            return .utility
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
    public let endTime: Date
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
    public var lmStudioEndpoint: String
    public var selectedModel: String
    public var analysisMode: AnalysisMode
    public var captureIntervalSeconds: Double
    public var batchDurationMinutes: Int
    public var idleTimeoutSeconds: Double
    public var diffThresholdPercent: Double
    public var retentionDays: Int
    public var autoAnalyze: Bool

    public static let `default` = UserSettings(
        lmStudioEndpoint: "http://127.0.0.1:1234/v1",
        selectedModel: "qwen3-vl-4b-instruct",
        analysisMode: .textFirst,
        captureIntervalSeconds: 20.0,
        batchDurationMinutes: 10,
        idleTimeoutSeconds: 120.0,
        diffThresholdPercent: 2.5,
        retentionDays: 7,
        autoAnalyze: true
    )
}
