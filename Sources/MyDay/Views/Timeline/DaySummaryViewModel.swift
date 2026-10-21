import Foundation
import SwiftUI
import AVFoundation

public struct DayCategoryStat: Identifiable {
    public var id: ActivityCategory { category }
    public let category: ActivityCategory
    public let duration: TimeInterval
    public let percentage: Double
}

public struct DayAppStat: Identifiable {
    public var id: String { bundleId.isEmpty ? appName : bundleId }
    public let appName: String
    public let bundleId: String
    public let duration: TimeInterval
    public let percentage: Double
}

@MainActor
public final class DaySummaryViewModel: ObservableObject {
    @Published public var isGeneratingVideo: Bool = false
    @Published public var videoPlayer: AVPlayer? = nil
    
    @Published public var totalDuration: TimeInterval = 0
    @Published public var totalCardsCount: Int = 0
    @Published public var totalFramesCount: Int = 0
    @Published public var categoryStats: [DayCategoryStat] = []
    @Published public var topApps: [DayAppStat] = []
    @Published public var totalVideoFrames: Int = 0
    @Published public var unfinishedTasks: [UnfinishedTask] = []
    @Published public var isLoadingTasks: Bool = false
    @Published public var copySuccessToast: Bool = false
    @Published public var playbackRate: Float = 1.0 // 0.5x (5fps), 1.0x (10fps), 2.0x (20fps)
    @Published public var isPlaying: Bool = true
    @Published public var currentTime: Double = 0.0
    @Published public var videoDuration: Double = 0.0
    
    private var currentDateKey: String = ""
    private var loopObserver: NSObjectProtocol? = nil
    private var timeObserverToken: Any? = nil

    public var progress: Double {
        guard videoDuration > 0 else { return 0 }
        return min(max(currentTime / videoDuration, 0), 1)
    }

    public func formatTime(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        let mins = max(0, s / 60)
        let secs = max(0, s % 60)
        return String(format: "%02d:%02d", mins, secs)
    }

    public init() {}

    public func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
        self.videoPlayer?.rate = rate
        self.isPlaying = (rate > 0)
    }

    public func togglePlayPause() {
        guard let p = videoPlayer else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            p.rate = playbackRate
            isPlaying = true
        }
    }

    public func restartVideo() {
        guard let p = videoPlayer else { return }
        let rate = self.playbackRate
        p.seek(to: .zero)
        p.play()
        p.rate = rate
        self.isPlaying = true
    }

    public func seek(to seconds: Double) {
        guard let p = videoPlayer else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let rate = isPlaying ? self.playbackRate : 0
        self.currentTime = seconds
        p.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                if rate > 0 {
                    p.rate = rate
                }
                self?.currentTime = seconds
            }
        }
    }
    
    public func loadSummary(cards: [TimelineCard], date: Date, appState: AppState) {
        self.totalCardsCount = cards.count
        self.totalDuration = cards.reduce(0.0) { $0 + $1.duration }
        self.totalFramesCount = cards.reduce(0) { $0 + $1.frameCount }
        
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        self.currentDateKey = df.string(from: date)

        // 1. Calculate Category Distribution
        var categoryDurations: [ActivityCategory: TimeInterval] = [:]
        for card in cards {
            categoryDurations[card.category, default: 0] += card.duration
        }
        
        let totalTime = max(1.0, self.totalDuration)
        self.categoryStats = categoryDurations.map { cat, dur in
            DayCategoryStat(
                category: cat,
                duration: dur,
                percentage: (dur / totalTime) * 100.0
            )
        }.sorted { $0.duration > $1.duration }
        
        // 2. Calculate Top App Usages
        var appDurations: [String: (appName: String, bundleId: String, duration: TimeInterval)] = [:]
        for card in cards {
            for usage in card.appUsages {
                let key = usage.bundleId.isEmpty ? usage.appName : usage.bundleId
                if var existing = appDurations[key] {
                    existing.duration += usage.durationSeconds
                    appDurations[key] = existing
                } else {
                    appDurations[key] = (usage.appName, usage.bundleId, usage.durationSeconds)
                }
            }
        }
        
        let totalAppTime = max(1.0, appDurations.values.reduce(0.0) { $0 + $1.duration })
        self.topApps = appDurations.values.map { item in
            DayAppStat(
                appName: item.appName,
                bundleId: item.bundleId,
                duration: item.duration,
                percentage: (item.duration / totalAppTime) * 100.0
            )
        }.sorted { $0.duration > $1.duration }

        // 3. Load or Extract Unfinished Tasks
        loadUnfinishedTasks(cards: cards, dateKey: self.currentDateKey, appState: appState)
        
        // 4. Compile Day Timelapse Video in background
        compileVideo(cards: cards)
    }

    private func loadUnfinishedTasks(cards: [TimelineCard], dateKey: String, appState: AppState) {
        guard !cards.isEmpty else {
            self.unfinishedTasks = []
            return
        }

        let userDefaultsKey = "myday_unfinished_tasks_\(dateKey)"

        // A. Check persisted tasks first
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode([UnfinishedTask].self, from: data),
           !saved.isEmpty {
            self.unfinishedTasks = saved
            return
        }

        // B. Instant local heuristic extraction (0ms latency fallback)
        let heuristicTasks = UnfinishedTasksExtractor.shared.extractTasks(from: cards)
        self.unfinishedTasks = heuristicTasks
        saveTasks(heuristicTasks, dateKey: dateKey)

        // C. Asynchronous AI extraction if LM Studio is connected
        if appState.isLMStudioConnected && appState.settings.autoAnalyze {
            self.isLoadingTasks = true
            Task {
                do {
                    let aiTasks = try await LMStudioClient.shared.extractUnfinishedTasks(
                        baseURL: appState.settings.lmStudioEndpoint,
                        model: appState.settings.selectedModel,
                        cards: cards
                    )

                    await MainActor.run {
                        self.isLoadingTasks = false
                        if !aiTasks.isEmpty {
                            // Preserve completion checkmarks if user already checked off items
                            var merged: [UnfinishedTask] = []
                            for var aiTask in aiTasks {
                                if let existing = self.unfinishedTasks.first(where: { $0.title.lowercased() == aiTask.title.lowercased() }) {
                                    aiTask.isCompleted = existing.isCompleted
                                }
                                merged.append(aiTask)
                            }
                            self.unfinishedTasks = merged
                            self.saveTasks(merged, dateKey: dateKey)
                        }
                    }
                } catch {
                    print("[DaySummary] AI task extraction error: \(error.localizedDescription)")
                    await MainActor.run {
                        self.isLoadingTasks = false
                    }
                }
            }
        }
    }

    public func toggleTaskCompletion(id: UUID) {
        if let index = unfinishedTasks.firstIndex(where: { $0.id == id }) {
            unfinishedTasks[index].isCompleted.toggle()
            saveTasks(unfinishedTasks, dateKey: currentDateKey)
        }
    }

    public func refreshTasks(cards: [TimelineCard], appState: AppState) {
        UserDefaults.standard.removeObject(forKey: "myday_unfinished_tasks_\(currentDateKey)")
        loadUnfinishedTasks(cards: cards, dateKey: currentDateKey, appState: appState)
    }

    public func copyTasksToMarkdown(date: Date) {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMMM yyyy"
        let dateStr = df.string(from: date)

        var md = "## Незавершенные дела за \(dateStr)\n\n"
        for task in unfinishedTasks {
            let check = task.isCompleted ? "[x]" : "[ ]"
            md += "- \(check) \(task.title) (\(task.appName))\n"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)

        self.copySuccessToast = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                self.copySuccessToast = false
            }
        }
    }

    private func saveTasks(_ tasks: [UnfinishedTask], dateKey: String) {
        guard !dateKey.isEmpty else { return }
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: "myday_unfinished_tasks_\(dateKey)")
        }
    }
    
    private func compileVideo(cards: [TimelineCard]) {
        guard !cards.isEmpty else { return }
        
        isGeneratingVideo = true
        Task {
            var allFrames: [URL] = []
            for card in cards {
                let frames = TimelapseStorage.shared.getFrames(between: card.startTime, and: card.endTime)
                allFrames.append(contentsOf: frames)
            }
            
            await MainActor.run {
                self.totalVideoFrames = allFrames.count
            }
            
            guard !allFrames.isEmpty else {
                await MainActor.run {
                    self.isGeneratingVideo = false
                }
                return
            }
            
            let tempDir = FileManager.default.temporaryDirectory
            let outURL = tempDir.appendingPathComponent("day_timelapse_\(UUID().uuidString).mp4")
            
            do {
                // 10 fps default for readable, smooth keyframe timelapse playback
                let videoURL = try await TimelapseGenerator.shared.generateTimelapseVideo(frameURLs: allFrames, outputURL: outURL, fps: 10)
                let p = AVPlayer(url: videoURL)
                await MainActor.run {
                    self.videoPlayer = p
                    self.isGeneratingVideo = false
                    self.isPlaying = true

                    if let obs = self.loopObserver {
                        NotificationCenter.default.removeObserver(obs)
                        self.loopObserver = nil
                    }

                    let currentRate = self.playbackRate
                    // Auto-loop day timelapse
                    self.loopObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: p.currentItem,
                        queue: .main
                    ) { [weak p] _ in
                        guard let p = p else { return }
                        p.seek(to: .zero)
                        p.play()
                        p.rate = currentRate
                    }

                    p.play()
                    p.rate = self.playbackRate
                    self.setupTimeObserver(for: p)
                }
            } catch {
                print("[DaySummary] Video error: \(error)")
                await MainActor.run {
                    self.isGeneratingVideo = false
                }
            }
        }
    }

    private func setupTimeObserver(for player: AVPlayer) {
        if let token = timeObserverToken {
            self.videoPlayer?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
            guard let self = self, let p = player else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentTime = time.seconds
                if let duration = p.currentItem?.duration.seconds, !duration.isNaN && duration > 0 {
                    self.videoDuration = duration
                }
            }
        }
    }
    
    public func cleanup() {
        if let token = timeObserverToken {
            self.videoPlayer?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
            loopObserver = nil
        }
        self.videoPlayer?.pause()
        self.videoPlayer = nil
        self.currentTime = 0.0
        self.videoDuration = 0.0
    }
    
    public static func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours) ч \(minutes) мин"
        } else {
            return "\(max(1, minutes)) мин"
        }
    }
}
