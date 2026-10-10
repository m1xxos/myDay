import Foundation
import SwiftUI
import AVFoundation

@MainActor
public final class DaySummaryViewModel: ObservableObject {
    @Published public var isGenerating: Bool = false
    @Published public var aiSummary: String = ""
    @Published public var videoPlayer: AVPlayer? = nil
    
    public init() {}
    
    public func generateSummary(for date: Date, cards: [TimelineCard], appState: AppState) {
        guard !cards.isEmpty else {
            self.aiSummary = "Нет активности за этот день."
            return
        }
        
        isGenerating = true
        self.aiSummary = "Анализирую день..."
        
        Task {
            // 1. Compile video
            await compileVideo(cards: cards)
            
            // 2. Request AI Summary
            await generateTextSummary(cards: cards, settings: appState.settings)
            
            isGenerating = false
        }
    }
    
    private func compileVideo(cards: [TimelineCard]) async {
        var allFrames: [URL] = []
        for card in cards {
            let frames = TimelapseStorage.shared.getFrames(between: card.startTime, and: card.endTime)
            allFrames.append(contentsOf: frames)
        }
        
        guard !allFrames.isEmpty else { return }
        
        let tempDir = FileManager.default.temporaryDirectory
        let outURL = tempDir.appendingPathComponent("day_timelapse_\(UUID().uuidString).mp4")
        
        do {
            // 60 fps for fast day summary
            let videoURL = try await TimelapseGenerator.shared.generateTimelapseVideo(frameURLs: allFrames, outputURL: outURL, fps: 60)
            let p = AVPlayer(url: videoURL)
            self.videoPlayer = p
            p.play()
        } catch {
            print("[DaySummary] Video error: \(error)")
        }
    }
    
    private func generateTextSummary(cards: [TimelineCard], settings: UserSettings) async {
        if !settings.autoAnalyze {
            self.aiSummary = "AI анализ выключен в настройках."
            return
        }
        
        let prompt = PromptTemplates.buildDaySummaryPrompt(cards: cards)
        do {
            let response = try await LMStudioClient.shared.analyzeActivity(
                baseURL: settings.lmStudioEndpoint,
                model: settings.selectedModel,
                userPrompt: prompt,
                keyframePath: nil,
                isVisionMode: false
            )
            // AIActivityResponse might fail if we asked for markdown, wait!
            // I should just use raw chat endpoint if I asked for markdown, 
            // but `analyzeActivity` forces JSON. 
            // Since it's a day summary, maybe I can just ask for JSON with a single "summary" field?
            self.aiSummary = response.summary
        } catch {
            // Because our LMStudioClient forces JSON parsing, let's just make it return JSON format in the prompt
            print("[DaySummary] AI error: \(error)")
            self.aiSummary = "Не удалось сгенерировать итоги: \(error.localizedDescription)"
        }
    }
}
