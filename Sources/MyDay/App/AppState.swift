import Foundation
import SwiftUI
import Combine

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    // MARK: - Published State
    @Published public var isRecording: Bool = true
    @Published public var isPaused: Bool = false
    @Published public var selectedDate: Date = Date()
    @Published public var cards: [TimelineCard] = []
    @Published public var availableModels: [String] = ["qwen3-vl-4b-instruct"]
    @Published public var settings: UserSettings = .default
    @Published public var currentWindowContext: WindowContext?
    @Published public var lastDiffPercent: Float = 0.0
    @Published public var isAnalyzing: Bool = false
    @Published public var toastMessage: String?
    @Published public var isLMStudioConnected: Bool = false
    @Published public var isShowingSettings: Bool = false
    @Published public var isShowingDaySummary: Bool = false
    @Published public var hasScreenPermission: Bool = true
    
    // Scrubber VM Cache
    public var scrubberVMs: [UUID: ScrubberViewModel] = [:]
    
    public func scrubberVM(for card: TimelineCard) -> ScrubberViewModel {
        if let vm = scrubberVMs[card.id] {
            return vm
        }
        let vm = ScrubberViewModel()
        scrubberVMs[card.id] = vm
        return vm
    }

    // MARK: - Private Services
    private var captureTimer: Timer?
    private var lastCaptureTime: Date = Date()
    private let db = DatabaseManager.shared
    private let captureManager = ScreenCaptureManager.shared
    private let idleMonitor = IdleMonitor.shared
    private let windowTracker = WindowTracker.shared
    private let differencer = FrameDifferencer.shared
    private let storage = TimelapseStorage.shared
    private let aggregator = BatchAggregator.shared
    private let lmStudio = LMStudioClient.shared

    public init() {
        loadSettings()
        loadCards(for: selectedDate)
        checkLMStudio()
        checkPermissions()
        startCaptureLoop()
        setupPermissionObservers()
        Task { [weak self] in
            await self?.performPeriodicCapture()
        }
    }

    private func setupPermissionObservers() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPermissions()
            }
        }

        // Lightweight watcher when permission is missing
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !self.hasScreenPermission {
                    self.checkPermissions()
                }
            }
        }
    }

    public func checkPermissions() {
        let granted = ScreenCaptureManager.shared.checkPermission()
        if granted != self.hasScreenPermission {
            self.hasScreenPermission = granted
            if granted {
                showToast("Разрешение получено! Запись активна")
                Task {
                    await self.performPeriodicCapture()
                }
            }
        }
    }

    public func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Settings Persistence

    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "myDaySettings"),
           let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            self.settings = decoded
        }
    }

    public func updateSettings(_ newSettings: UserSettings) {
        self.settings = newSettings
        if let encoded = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(encoded, forKey: "myDaySettings")
        }
        // Restart capture loop with new interval if changed
        startCaptureLoop()
    }

    // MARK: - LM Studio Probing

    public func checkLMStudio() {
        Task {
            do {
                let models = try await lmStudio.fetchAvailableModels(baseURL: settings.lmStudioEndpoint)
                self.availableModels = models
                self.isLMStudioConnected = true
                if !models.contains(settings.selectedModel), let first = models.first {
                    self.settings.selectedModel = first
                    self.updateSettings(self.settings)
                }
            } catch {
                self.isLMStudioConnected = false
            }
        }
    }

    // MARK: - Cards Loading

    public func loadCards(for date: Date) {
        self.selectedDate = date
        self.cards = db.fetchCards(for: date)
    }

    public func deleteCard(_ card: TimelineCard) {
        db.deleteCard(id: card.id)
        loadCards(for: selectedDate)
    }

    // MARK: - Capture Loop

    public func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            startCaptureLoop()
        } else {
            stopCaptureLoop()
        }
    }

    public func togglePause() {
        isPaused.toggle()
    }

    private func startCaptureLoop() {
        captureTimer?.invalidate()
        lastCaptureTime = Date()

        captureTimer = Timer.scheduledTimer(withTimeInterval: settings.captureIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performPeriodicCapture()
            }
        }
    }

    private func stopCaptureLoop() {
        captureTimer?.invalidate()
        captureTimer = nil
    }

    private func performPeriodicCapture() async {
        guard isRecording && !isPaused else { return }

        // 1. Check Idle
        if idleMonitor.isUserIdle(timeoutSeconds: settings.idleTimeoutSeconds) {
            return
        }

        let now = Date()
        let sliceDuration = max(1, now.timeIntervalSince(lastCaptureTime))
        lastCaptureTime = now

        // 2. Window context
        let context = windowTracker.getCurrentContext()
        self.currentWindowContext = context

        // 3. Screen Capture (optional; do not block activity tracking if capture is pending permission)
        let cgImage = await captureManager.captureMainDisplay()
        var recordedFrame: RecordedFrame? = nil

        if let cgImage = cgImage {
            // 4. Perceptual Diff check
            let (diffPercent, isSignificant, _) = differencer.calculateDifference(for: cgImage)
            self.lastDiffPercent = diffPercent

            // If screen changed significantly OR active window changed, save frame
            if isSignificant || diffPercent >= Float(settings.diffThresholdPercent) {
                if let savedPath = storage.saveFrame(image: cgImage, timestamp: now) {
                    recordedFrame = RecordedFrame(
                        timestamp: now,
                        filePath: savedPath,
                        appName: context.appName,
                        windowTitle: context.windowTitle,
                        diffScore: diffPercent,
                        isKeyframe: isSignificant
                    )
                }
            }
        }

        // 5. Always record activity slice
        aggregator.recordActivity(frame: recordedFrame, context: context, duration: sliceDuration)

        // 6. Check if batch duration expired
        if aggregator.hasEnoughData(minDurationSeconds: TimeInterval(settings.batchDurationMinutes * 60)) {
            await triggerBatchAnalysis()
        }
    }

    // MARK: - Manual or Timed Analysis Trigger

    public func triggerBatchAnalysis() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true

        // Ensure current context is recorded right now before finalizing
        let context = windowTracker.getCurrentContext()
        self.currentWindowContext = context

        let cgImage = await captureManager.captureMainDisplay()
        var frame: RecordedFrame? = nil
        if let cgImage = cgImage {
            if let savedPath = storage.saveFrame(image: cgImage, timestamp: Date()) {
                frame = RecordedFrame(
                    timestamp: Date(),
                    filePath: savedPath,
                    appName: context.appName,
                    windowTitle: context.windowTitle,
                    diffScore: 100.0,
                    isKeyframe: true
                )
            }
        }

        aggregator.recordActivity(frame: frame, context: context, duration: 60.0)

        let card = await aggregator.finalizeBatch(settings: settings, forceImmediate: true)
        isAnalyzing = false

        // Always reload cards for the active day
        self.selectedDate = Date()
        loadCards(for: Date())

        if let card = card {
            showToast("Создан блок: \(card.title)")
        } else {
            showToast("Блок активности сформирован")
        }
    }

    public func copyObsidianDay() {
        let text = ObsidianExporter.shared.exportDayToMarkdown(date: selectedDate, cards: cards)
        ObsidianExporter.shared.copyToClipboard(text)
        showToast("Таймлайн скопирован для Obsidian!")
    }

    public func copyObsidianCard(_ card: TimelineCard) {
        let text = ObsidianExporter.shared.exportCardToMarkdown(card)
        ObsidianExporter.shared.copyToClipboard(text)
        showToast("Блок скопирован для Obsidian!")
    }

    public func showToast(_ message: String) {
        self.toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }
}
