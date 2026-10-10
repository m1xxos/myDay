import Foundation
import CoreGraphics
import AppKit

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
        lock.lock()
        defer { lock.unlock() }

        let app = context.appName
        if var slice = appUsages[app] {
            slice.durationSeconds += duration
            if !slice.windowTitles.contains(context.windowTitle) && !context.windowTitle.isEmpty {
                slice.windowTitles.append(context.windowTitle)
            }
            appUsages[app] = slice
        } else {
            appUsages[app] = AppUsageSlice(
                appName: app,
                bundleId: context.bundleId,
                durationSeconds: duration,
                windowTitles: context.windowTitle.isEmpty ? [] : [context.windowTitle]
            )
        }

        if let frame = frame {
            frames.append(frame)
        }

        lastRecordedTime = Date()
    }

    public func hasEnoughData(minDurationSeconds: TimeInterval = 60.0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = lastRecordedTime.timeIntervalSince(batchStartTime)
        return elapsed >= minDurationSeconds && !appUsages.isEmpty
    }

    public func finalizeBatch(
        settings: UserSettings,
        forceImmediate: Bool = false
    ) async -> TimelineCard? {
        let (currentStart, currentEnd, currentAppUsages, currentFrames) = snapshotAndReset()

        var appSlices = Array(currentAppUsages.values)
        if appSlices.isEmpty {
            let ctx = WindowTracker.shared.getCurrentContext()
            appSlices = [AppUsageSlice(
                appName: ctx.appName,
                bundleId: ctx.bundleId,
                durationSeconds: 60.0,
                windowTitles: ctx.windowTitle.isEmpty ? [] : [ctx.windowTitle]
            )]
        }

        let duration = max(60, currentEnd.timeIntervalSince(currentStart))
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let rangeStr = "\(timeFormatter.string(from: currentStart)) – \(timeFormatter.string(from: currentEnd)) (\(max(1, Int(duration / 60))) min)"

        // Pick best keyframe
        let keyframe = currentFrames.max(by: { $0.diffScore < $1.diffScore }) ?? currentFrames.last
        var ocrKeywords: [String] = []
        var keyTextLines: [String] = []

        // Run Apple Neural Engine OCR locally on keyframe if available
        if let keyframe = keyframe, let cgImage = loadCGImage(from: keyframe.filePath) {
            let ocrResult = await TextRecognitionService.shared.recognizeText(from: cgImage)
            ocrKeywords = ocrResult.keywords
            keyTextLines = ocrResult.keyLines
        }

        let primaryApp = appSlices.max(by: { $0.durationSeconds < $1.durationSeconds })?.appName ?? "Mac"

        var cardTitle = "Работа в \(primaryApp)"
        var cardSummary = "Сессия активности в приложениях: " + appSlices.map { $0.appName }.joined(separator: ", ")
        var cardCategory = ActivityCategory.match(from: primaryApp)
        var cardTags: [String] = [primaryApp.lowercased()]
        var isAnalyzed = false
        var isContinuation = false

        let lastCard = DatabaseManager.shared.fetchAllCards(limit: 1).first
        
        // We only allow stitching if the last card ended recently (e.g. less than 20 minutes ago)
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
                cardCategory = ActivityCategory.match(from: aiResponse.category)
                cardTags = aiResponse.tags
                isContinuation = aiResponse.is_continuation
                isAnalyzed = true
            } catch {
                print("[BatchAggregator] LM Studio call skipped/failed: \(error.localizedDescription). Falling back to heuristic card.")
                
                // Heuristic stitching fallback
                if let last = lastCard, last.category == cardCategory, currentStart.timeIntervalSince(last.endTime) < 5 * 60 {
                    isContinuation = true
                }
            }
        } else {
             // Heuristic stitching fallback if autoAnalyze is off
            if let last = lastCard, last.category == cardCategory, currentStart.timeIntervalSince(last.endTime) < 5 * 60 {
                isContinuation = true
            }
        }

        if isContinuation, var mergedCard = lastCard {
            // Update mergedCard with combined data
            mergedCard.endTime = currentEnd
            mergedCard.frameCount += currentFrames.count
            mergedCard.title = isAnalyzed ? cardTitle : mergedCard.title
            mergedCard.summary = isAnalyzed ? cardSummary : mergedCard.summary
            
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
            
            mergedCard.category = cardCategory
            mergedCard.keyframePath = keyframe?.filePath ?? mergedCard.keyframePath
            
            DatabaseManager.shared.saveCard(mergedCard)
            return mergedCard
        } else {
            let card = TimelineCard(
                startTime: currentStart,
                endTime: currentEnd,
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

    private func snapshotAndReset() -> (Date, Date, [String: AppUsageSlice], [RecordedFrame]) {
        lock.lock()
        defer { lock.unlock() }

        let start = batchStartTime
        let end = Date()
        let usages = appUsages
        let recordedFrames = frames

        // Reset
        self.batchStartTime = end
        self.appUsages = [:]
        self.frames = []
        self.lastRecordedTime = end

        return (start, end, usages, recordedFrames)
    }

    private func loadCGImage(from path: String) -> CGImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
