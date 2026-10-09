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

        // Try AI analysis via LM Studio if enabled
        if settings.autoAnalyze {
            let prompt = PromptTemplates.buildUserPrompt(
                timeRangeString: rangeStr,
                appUsages: appSlices,
                ocrKeywords: ocrKeywords,
                keyTextLines: keyTextLines
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
                isAnalyzed = true
            } catch {
                print("[BatchAggregator] LM Studio call skipped/failed: \(error.localizedDescription). Falling back to heuristic card.")
            }
        }

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
