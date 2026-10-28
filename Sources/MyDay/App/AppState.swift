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
    @Published public var selectedCard: TimelineCard? = nil
    @Published public var isInspectorVisible: Bool = true
    @Published public var isShowingCinemaModal: Bool = false
    @Published public var cinemaCard: TimelineCard? = nil
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
    private var dailyCleanupTimer: Timer?
    private var lastCaptureTime: Date = Date()
    private var lastSavedFrameTime: Date?
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
        _ = db.sanitizeAndFixCrossDayCards()
        _ = db.consolidateAdjacentCards()
        performDailyCleanupIfNeeded()
        setupDailyCleanupTimer()
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

        // System Sleep & Screen Lock Observers
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.aggregator.hasEnoughData(minDurationSeconds: 60.0) {
                    await self.triggerBatchAnalysis()
                }
            }
        }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.aggregator.hasEnoughData(minDurationSeconds: 60.0) {
                    await self.triggerBatchAnalysis()
                }
            }
        }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.aggregator.hasEnoughData(minDurationSeconds: 60.0) {
                    await self.triggerBatchAnalysis()
                }
            }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastCaptureTime = Date()
            }
        }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastCaptureTime = Date()
            }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.lastCaptureTime = Date()
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
        Task { @MainActor in
            let granted = await ScreenCaptureManager.shared.verifyPermissionAsync()
            if granted != self.hasScreenPermission {
                self.hasScreenPermission = granted
                if granted {
                    showToast("Разрешение получено! Запись активна")
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
        storage.runCleanup(settings: newSettings)
        // Restart capture loop with new interval if changed
        startCaptureLoop()
        if newSettings.engineMode == .lmStudio {
            checkLMStudio()
        } else {
            self.isLMStudioConnected = false
        }
    }

    // MARK: - Daily Storage Cleanup

    public func performDailyCleanupIfNeeded(force: Bool = false) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let todayKey = df.string(from: Date())
        let lastKey = UserDefaults.standard.string(forKey: "myDay_last_daily_cleanup_key") ?? ""

        if force || todayKey != lastKey {
            print("[AppState] Running daily storage cleanup (Policy: \(settings.cleanupPolicy.rawValue))...")
            storage.runCleanup(settings: settings)
            UserDefaults.standard.set(todayKey, forKey: "myDay_last_daily_cleanup_key")
        }
    }

    private func setupDailyCleanupTimer() {
        dailyCleanupTimer?.invalidate()
        // Check once an hour whether a new day has arrived to perform daily cleanup
        dailyCleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performDailyCleanupIfNeeded()
            }
        }
    }

    // MARK: - LM Studio Probing

    public func checkLMStudio() {
        guard settings.engineMode == .lmStudio else {
            self.isLMStudioConnected = false
            return
        }
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
        if selectedCard == nil || !cards.contains(where: { $0.id == selectedCard?.id }) {
            self.selectedCard = cards.last ?? cards.first
        }
    }

    public func selectCard(_ card: TimelineCard) {
        self.selectedCard = card
        self.isInspectorVisible = true
    }

    public func openCinemaPlayer(for card: TimelineCard) {
        self.cinemaCard = card
        let vm = scrubberVM(for: card)
        vm.loadFrames(for: card)
        vm.currentFrameIndex = 0
        self.isShowingCinemaModal = true
    }

    public func deleteCard(_ card: TimelineCard) {
        db.deleteCard(id: card.id)
        if selectedCard?.id == card.id {
            selectedCard = nil
        }
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

        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastCaptureTime)

        // 1. Long Sleep/Idle Gap Detection (e.g. laptop lid closed or suspended)
        // If more than 3 minutes (or idleTimeoutSeconds) passed since last capture tick:
        if timeSinceLast > Double(min(settings.idleTimeoutSeconds, 180)) {
            print("[AppState] Detected sleep/wake gap: \(Int(timeSinceLast))s since last capture.")
            if aggregator.hasAnyData() {
                _ = await aggregator.finalizePreGapBatch(settings: settings)
                loadCards(for: selectedDate)
            } else {
                aggregator.reset()
            }
            lastCaptureTime = now
            return
        }

        // 2. Idle Monitor (user stepped away while screen was on)
        let isIdle = idleMonitor.isUserIdle(timeoutSeconds: settings.idleTimeoutSeconds)
        if isIdle {
            if aggregator.hasAnyData() {
                _ = await aggregator.finalizePreGapBatch(settings: settings)
                loadCards(for: selectedDate)
            }
            lastCaptureTime = now
            return
        }

        // 3. Midnight Day Boundary Check (never leak yesterday's batch into today)
        let calendar = Calendar.current
        if !calendar.isDate(aggregator.currentBatchStartTime, inSameDayAs: now) {
            print("[AppState] Midnight crossed. Finalizing previous day's batch.")
            if aggregator.hasAnyData() {
                _ = await aggregator.finalizeBatch(settings: settings)
                loadCards(for: selectedDate)
            } else {
                aggregator.reset()
            }
        }

        lastCaptureTime = now

        // 4. Window context
        let context = windowTracker.getCurrentContext()
        self.currentWindowContext = context

        // Ignore lock screen, screensaver, loginwindow
        if windowTracker.isSystemLockOrScreensaver(context: context) {
            if aggregator.hasAnyData() {
                _ = await aggregator.finalizePreGapBatch(settings: settings)
                loadCards(for: selectedDate)
            }
            return
        }

        // Automatic exclusion of private / incognito browser windows
        if settings.excludePrivateBrowsing && context.isPrivateBrowsing {
            if aggregator.hasAnyData() {
                _ = await aggregator.finalizePreGapBatch(settings: settings)
                loadCards(for: selectedDate)
            }
            return
        }

        // 4. Safe slice duration (capped to at most 1.5x capture interval)
        let sliceDuration = max(1.0, min(timeSinceLast, Double(settings.captureIntervalSeconds * 1.5)))

        // 5. Screen Capture
        let cgImage = await captureManager.captureMainDisplay()
        var recordedFrame: RecordedFrame? = nil

        if let cgImage = cgImage {
            // Auto-clear permission banner if a frame is successfully captured
            if !self.hasScreenPermission {
                self.hasScreenPermission = true
            }

            // Perceptual Diff check
            let (diffPercent, isSignificant, _) = differencer.calculateDifference(for: cgImage)
            self.lastDiffPercent = diffPercent

            // Check if screen changed significantly, active window changed, OR heartbeat interval (75s) expired
            let isHeartbeat = (lastSavedFrameTime == nil) || (now.timeIntervalSince(lastSavedFrameTime!) >= 75.0)
            let shouldSaveFrame = isSignificant || (diffPercent >= Float(settings.diffThresholdPercent)) || isHeartbeat

            if shouldSaveFrame {
                if let savedPath = storage.saveFrame(image: cgImage, timestamp: now) {
                    self.lastSavedFrameTime = now
                    recordedFrame = RecordedFrame(
                        timestamp: now,
                        filePath: savedPath,
                        appName: context.appName,
                        windowTitle: context.windowTitle,
                        diffScore: diffPercent,
                        isKeyframe: isSignificant || isHeartbeat
                    )
                }
            }
        }

        // 6. Record activity slice
        aggregator.recordActivity(frame: recordedFrame, context: context, duration: sliceDuration)

        // 7. Check if batch duration expired
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

        let isBlocked = (settings.excludePrivateBrowsing && context.isPrivateBrowsing) || windowTracker.isSystemLockOrScreensaver(context: context)

        if !isBlocked {
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
        }

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

    public func consolidateFragmentedCards() {
        let count = db.consolidateAdjacentCards()
        loadCards(for: selectedDate)
        if count > 0 {
            showToast("Склеено \(count) фрагментов в цельные сессии!")
        } else {
            showToast("Все блоки уже оптимально объединены")
        }
    }
}
