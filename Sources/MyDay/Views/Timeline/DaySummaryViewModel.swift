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
    
    public init() {}
    
    public func loadSummary(cards: [TimelineCard]) {
        self.totalCardsCount = cards.count
        self.totalDuration = cards.reduce(0.0) { $0 + $1.duration }
        self.totalFramesCount = cards.reduce(0) { $0 + $1.frameCount }
        
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
        
        // 3. Compile Day Timelapse Video in background
        compileVideo(cards: cards)
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
                // 60 fps for fast day summary video
                let videoURL = try await TimelapseGenerator.shared.generateTimelapseVideo(frameURLs: allFrames, outputURL: outURL, fps: 60)
                let p = AVPlayer(url: videoURL)
                await MainActor.run {
                    self.videoPlayer = p
                    self.isGeneratingVideo = false
                    p.play()
                }
            } catch {
                print("[DaySummary] Video error: \(error)")
                await MainActor.run {
                    self.isGeneratingVideo = false
                }
            }
        }
    }
    
    public func cleanup() {
        self.videoPlayer?.pause()
        self.videoPlayer = nil
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
