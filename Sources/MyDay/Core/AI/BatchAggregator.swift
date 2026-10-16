import Foundation
import CoreGraphics
import AppKit
import ImageIO

public final class BatchAggregator: @unchecked Sendable {
    public static let shared = BatchAggregator()

    private let lock = NSLock()
    private var batchStartTime: Date = Date()
    private var frames: [RecordedFrame] = []
    private var appUsages: [String: AppUsageSlice] = [:]
    private var lastRecordedTime: Date = Date()

    public init() {}

    public func recordActivity(
        frame: RecordedFrame?,
        context: WindowContext,
        duration: TimeInterval
    ) {
        if context.isPrivateBrowsing {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        // Sanity cap: slice duration should never exceed 60 seconds
        let safeDuration = min(duration, 60.0)

        let app = context.appName
        if var slice = appUsages[app] {
            slice.durationSeconds += safeDuration
            if !slice.windowTitles.contains(context.windowTitle) && !context.windowTitle.isEmpty {
                slice.windowTitles.append(context.windowTitle)
            }
            appUsages[app] = slice
        } else {
            appUsages[app] = AppUsageSlice(
                appName: app,
                bundleId: context.bundleId,
                durationSeconds: safeDuration,
                windowTitles: context.windowTitle.isEmpty ? [] : [context.windowTitle]
            )
        }

        if let frame = frame {
            frames.append(frame)
        }

        lastRecordedTime = Date()
    }

    public var currentBatchStartTime: Date {
        lock.lock()
        defer { lock.unlock() }
        return batchStartTime
    }

    public func hasAnyData() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !appUsages.isEmpty || !frames.isEmpty
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        self.batchStartTime = now
        self.appUsages = [:]
        self.frames = []
        self.lastRecordedTime = now
    }

    public func hasEnoughData(minDurationSeconds: TimeInterval = 60.0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = lastRecordedTime.timeIntervalSince(batchStartTime)
        return elapsed >= minDurationSeconds && !appUsages.isEmpty
    }

    public func finalizePreGapBatch(settings: UserSettings) async -> TimelineCard? {
        return await finalizeBatch(settings: settings, isPreGap: true)
    }

    public func finalizeBatch(
        settings: UserSettings,
        forceImmediate: Bool = false,
        isPreGap: Bool = false
    ) async -> TimelineCard? {
        let (currentStart, currentEnd, currentAppUsages, currentFrames) = snapshotAndReset(isPreGap: isPreGap)

        var appSlices = Array(currentAppUsages.values)
        let totalActiveSeconds = appSlices.reduce(0.0) { $0 + $1.durationSeconds }

        // If pre-gap batch has virtually no activity and no frames, discard it cleanly
        if isPreGap && totalActiveSeconds < 15.0 && currentFrames.isEmpty {
            return nil
        }
        if appSlices.isEmpty {
            let ctx = WindowTracker.shared.getCurrentContext()
            appSlices = [AppUsageSlice(
                appName: ctx.appName,
                bundleId: ctx.bundleId,
                durationSeconds: 60.0,
                windowTitles: ctx.windowTitle.isEmpty ? [] : [ctx.windowTitle]
            )]
        }

        // HARD GUARDRAIL 1: Safe End Time. Never let wall-clock time stretch over idle/sleep gaps.
        let maxAllowedSpan = max(60.0, totalActiveSeconds + 120.0)
        var safeEnd = currentEnd
        if safeEnd.timeIntervalSince(currentStart) > maxAllowedSpan {
            safeEnd = currentStart.addingTimeInterval(maxAllowedSpan)
        }

        // HARD GUARDRAIL 2: NEVER cross midnight / different calendar days!
        let calendar = Calendar.current
        if !calendar.isDate(currentStart, inSameDayAs: safeEnd) {
            if let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentStart) {
                safeEnd = endOfDay
            }
        }

        let duration = max(60.0, safeEnd.timeIntervalSince(currentStart))
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let rangeStr = "\(timeFormatter.string(from: currentStart)) – \(timeFormatter.string(from: safeEnd)) (\(max(1, Int(duration / 60))) min)"

        // 1. Identify dominant app and check if it is remote desktop/VM
        let sortedApps = appSlices.sorted(by: { $0.durationSeconds > $1.durationSeconds })
        let primaryAppSlice = sortedApps.first
        let primaryApp = primaryAppSlice?.appName ?? "Mac"
        let isPrimaryRemote = WindowTracker.isRemoteDesktopOrVM(appName: primaryApp, bundleId: primaryAppSlice?.bundleId ?? "")

        // 2. Select keyframe: prioritize frames belonging to the dominant app (especially if remote desktop)
        let dominantFrames = currentFrames.filter { $0.appName == primaryApp }
        let keyframe: RecordedFrame?
        if !dominantFrames.isEmpty {
            keyframe = dominantFrames.max(by: { $0.diffScore < $1.diffScore }) ?? dominantFrames.last
        } else {
            keyframe = currentFrames.max(by: { $0.diffScore < $1.diffScore }) ?? currentFrames.last
        }

        var ocrKeywords: [String] = []
        var keyTextLines: [String] = []

        // Multi-frame OCR: prioritize dominant app frames to extract deep context
        var framesToOcr: [RecordedFrame] = []
        if let kf = keyframe {
            framesToOcr.append(kf)
        }
        if isPrimaryRemote && dominantFrames.count > 1 {
            // Also sample another frame from remote session (e.g. earlier distinct frame)
            if let secondFrame = dominantFrames.first(where: { $0.filePath != keyframe?.filePath }) {
                framesToOcr.append(secondFrame)
            }
        }

        for frame in framesToOcr {
            if let cgImage = loadCGImage(from: frame.filePath) {
                let ocrResult = await TextRecognitionService.shared.recognizeText(from: cgImage)
                for kw in ocrResult.keywords {
                    if !ocrKeywords.contains(kw) && ocrKeywords.count < 20 {
                        ocrKeywords.append(kw)
                    }
                }
                for line in ocrResult.keyLines {
                    if !keyTextLines.contains(line) && keyTextLines.count < 25 {
                        keyTextLines.append(line)
                    }
                }
            }
        }

        var cardTitle = "Работа в \(primaryApp)"
        var cardSummary = "Сессия активности в приложениях: " + appSlices.map { $0.appName }.joined(separator: ", ")
        var cardCategory = ActivityCategory.match(from: primaryApp, ocrKeywords: ocrKeywords)
        var cardTags: [String] = [primaryApp.lowercased()]
        var isAnalyzed = false
        var isContinuationAI = false

        let lastCard = DatabaseManager.shared.fetchAllCards(limit: 1).first
        
        // Context for LLM prompt if last card ended within 20 minutes
        var previousContext: (title: String, summary: String)? = nil
        if let last = lastCard, currentStart.timeIntervalSince(last.endTime) < 20 * 60 {
            previousContext = (title: last.title, summary: last.summary)
        }

        // Try AI analysis via LM Studio if enabled
        if settings.autoAnalyze {
            let prompt = PromptTemplates.buildUserPrompt(
                timeRangeString: rangeStr,
                appUsages: appSlices,
                ocrKeywords: ocrKeywords,
                keyTextLines: keyTextLines,
                previousContext: previousContext
            )

            do {
                let aiResponse = try await LMStudioClient.shared.analyzeActivity(
                    baseURL: settings.lmStudioEndpoint,
                    model: settings.selectedModel,
                    userPrompt: prompt,
                    keyframePath: keyframe?.filePath,
                    isVisionMode: settings.analysisMode == .visionAssisted
                )

                cardTitle = aiResponse.title
                cardSummary = aiResponse.summary
                cardCategory = ActivityCategory.match(from: aiResponse.category, ocrKeywords: ocrKeywords)
                cardTags = aiResponse.tags
                isContinuationAI = aiResponse.is_continuation
                isAnalyzed = true
            } catch {
                print("[BatchAggregator] LM Studio call skipped/failed: \(error.localizedDescription). Falling back to heuristic card.")
            }
        }

        // Deterministic Multi-Tier Stitching Check
        let shouldStitch: Bool
        if let last = lastCard {
            shouldStitch = Self.canStitchSessions(
                lastCard: last,
                currentStart: currentStart,
                currentEnd: safeEnd,
                newTitle: cardTitle,
                newCategory: cardCategory,
                newApps: appSlices,
                isAIContinuation: isContinuationAI
            )
        } else {
            shouldStitch = false
        }

        if shouldStitch, var mergedCard = lastCard {
            print("[BatchAggregator] Stitching batch with previous session '\(mergedCard.title)' (ID: \(mergedCard.id))")
            // Update mergedCard with combined data
            mergedCard.endTime = min(safeEnd, mergedCard.startTime.addingTimeInterval(3 * 3600))
            mergedCard.frameCount += currentFrames.count
            
            // If current card was analyzed by AI or has more descriptive title, update title & category
            if isAnalyzed {
                if !mergedCard.isAIAnalyzed || mergedCard.title.starts(with: "Работа в ") || isPrimaryRemote {
                    mergedCard.title = cardTitle
                    mergedCard.category = cardCategory
                }
                mergedCard.isAIAnalyzed = true
                if !cardSummary.isEmpty && cardSummary != mergedCard.summary {
                    mergedCard.summary = cardSummary
                }
            }
            
            // Merge app usages
            var combinedUsages = mergedCard.appUsages
            for newUsage in appSlices {
                if let index = combinedUsages.firstIndex(where: { $0.appName == newUsage.appName }) {
                    combinedUsages[index].durationSeconds += newUsage.durationSeconds
                    for title in newUsage.windowTitles {
                        if !combinedUsages[index].windowTitles.contains(title) {
                            combinedUsages[index].windowTitles.append(title)
                        }
                    }
                } else {
                    combinedUsages.append(newUsage)
                }
            }
            mergedCard.appUsages = combinedUsages
            
            // Merge tags
            for tag in cardTags {
                if !mergedCard.tags.contains(tag) {
                    mergedCard.tags.append(tag)
                }
            }

            // Merge OCR keywords
            for kw in ocrKeywords {
                if !mergedCard.ocrKeywords.contains(kw) {
                    mergedCard.ocrKeywords.append(kw)
                }
            }
            
            if let kf = keyframe {
                mergedCard.keyframePath = kf.filePath
            }
            
            DatabaseManager.shared.saveCard(mergedCard)
            return mergedCard
        } else {
            let card = TimelineCard(
                startTime: currentStart,
                endTime: safeEnd,
                title: cardTitle,
                summary: cardSummary,
                category: cardCategory,
                tags: cardTags,
                appUsages: appSlices,
                keyframePath: keyframe?.filePath,
                timelapseVideoPath: nil,
                frameCount: currentFrames.count,
                isAIAnalyzed: isAnalyzed,
                ocrKeywords: ocrKeywords
            )

            DatabaseManager.shared.saveCard(card)
            return card
        }
    }

    private func snapshotAndReset(isPreGap: Bool = false) -> (Date, Date, [String: AppUsageSlice], [RecordedFrame]) {
        lock.lock()
        defer { lock.unlock() }

        let start = batchStartTime
        let end = isPreGap ? lastRecordedTime : min(Date(), lastRecordedTime.addingTimeInterval(60.0))
        let usages = appUsages
        let recordedFrames = frames

        // Reset
        let now = Date()
        self.batchStartTime = now
        self.appUsages = [:]
        self.frames = []
        self.lastRecordedTime = now

        return (start, end, usages, recordedFrames)
    }

    private func loadCGImage(from path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Multi-Tier Deterministic Stitching Heuristics

    public static func canStitchSessions(
        lastCard: TimelineCard,
        currentStart: Date,
        currentEnd: Date,
        newTitle: String,
        newCategory: ActivityCategory,
        newApps: [AppUsageSlice],
        isAIContinuation: Bool
    ) -> Bool {
        // 0. Calendar day check: MUST be on the exact same calendar day!
        let calendar = Calendar.current
        guard calendar.isDate(lastCard.startTime, inSameDayAs: currentStart) &&
              calendar.isDate(lastCard.endTime, inSameDayAs: currentEnd) &&
              calendar.isDate(currentStart, inSameDayAs: currentEnd) else {
            return false
        }

        // 1. Time gap check (must be within 15 minutes)
        let gap = currentStart.timeIntervalSince(lastCard.endTime)
        guard gap >= -60 && gap <= 15 * 60 else { return false }

        // 2. Max combined duration guardrail (never exceed 3 hours in a single continuous block)
        let totalSpan = currentEnd.timeIntervalSince(lastCard.startTime)
        guard totalSpan <= 3 * 3600 else { return false }

        // Tier 1: Explicit AI confirmation
        if isAIContinuation {
            return true
        }

        let cleanLastTitle = lastCard.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanNewTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Tier 2: Exact title match (e.g. adjacent YouTube, Formula-1, Docker blocks)
        if !cleanLastTitle.isEmpty && cleanLastTitle == cleanNewTitle {
            return true
        }

        // Tier 3: Fuzzy title similarity >= 0.60 within the same category
        if lastCard.category == newCategory {
            let sim = titleSimilarity(cleanLastTitle, cleanNewTitle)
            if sim >= 0.60 {
                return true
            }
        }

        // Tier 4: Dominant application match (> 65% in same app) and same category within 10 min gap
        if gap <= 10 * 60 && lastCard.category == newCategory {
            let totalNewSec = newApps.reduce(0.0) { $0 + $1.durationSeconds }
            if let topNew = newApps.max(by: { $0.durationSeconds < $1.durationSeconds }), totalNewSec > 0 {
                let newRatio = topNew.durationSeconds / totalNewSec
                if newRatio >= 0.65 {
                    let totalLastSec = lastCard.appUsages.reduce(0.0) { $0 + $1.durationSeconds }
                    if let topLast = lastCard.appUsages.max(by: { $0.durationSeconds < $1.durationSeconds }), totalLastSec > 0 {
                        if topNew.appName == topLast.appName {
                            return true
                        }
                    }
                }
            }
        }

        return false
    }

    public static func titleSimilarity(_ s1: String, _ s2: String) -> Double {
        guard !s1.isEmpty && !s2.isEmpty else { return 0.0 }
        if s1 == s2 { return 1.0 }

        let stopWords: Set<String> = ["в", "и", "на", "с", "по", "для", "о", "об", "от", "до", "за", "к", "a", "the", "in", "on", "at", "to", "for", "with", "and"]
        let words1 = Set(s1.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) })
        let words2 = Set(s2.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) })

        guard !words1.isEmpty && !words2.isEmpty else { return 0.0 }
        let intersection = words1.intersection(words2)
        let minCount = min(words1.count, words2.count)
        guard minCount > 0 else { return 0.0 }

        // Overlap coefficient: ratio of shared content words to the shorter title
        return Double(intersection.count) / Double(minCount)
    }
}
