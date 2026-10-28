import Testing
import Foundation
import CoreGraphics
@testable import MyDay

@Suite("MyDay Core Engine Tests")
struct MyDayTests {

    // MARK: - Frame Differencer Tests

    @Test("FrameDifferencer accurately detects identical frames")
    func testFrameDifferencerIdentical() throws {
        let differencer = FrameDifferencer()

        // Create a solid red 100x100 test image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context1 = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context1.setFillColor(CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0))
        context1.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let img1 = context1.makeImage()!

        // First frame initializes baseline
        let res1 = differencer.calculateDifference(for: img1)
        #expect(res1.diffPercent == 100.0)

        // Same image should have 0% difference
        let res2 = differencer.calculateDifference(for: img1)
        #expect(res2.diffPercent < 0.01)
        #expect(res2.isSignificant == false)
    }

    @Test("FrameDifferencer detects distinct frames")
    func testFrameDifferencerDistinct() throws {
        let differencer = FrameDifferencer()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Black image
        let contextBlack = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        contextBlack.setFillColor(CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0))
        contextBlack.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let imgBlack = contextBlack.makeImage()!

        // White image
        let contextWhite = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        contextWhite.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        contextWhite.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let imgWhite = contextWhite.makeImage()!

        _ = differencer.calculateDifference(for: imgBlack)
        let resWhite = differencer.calculateDifference(for: imgWhite)

        #expect(resWhite.diffPercent > 80.0)
        #expect(resWhite.isSignificant == true)
    }

    // MARK: - Obsidian Exporter Tests

    @Test("ObsidianExporter formats valid YAML frontmatter and callouts")
    func testObsidianExport() throws {
        let card1 = TimelineCard(
            startTime: Date(timeIntervalSince1970: 1700000000),
            endTime: Date(timeIntervalSince1970: 1700000900), // 15 mins
            title: "Разработка ядра MyDay",
            summary: "Написал ScreenCaptureManager и Unit Tests",
            category: .development,
            tags: ["swift", "macos"],
            appUsages: [
                AppUsageSlice(appName: "Xcode", bundleId: "com.apple.dt.Xcode", durationSeconds: 600, windowTitles: ["MyDayApp.swift"]),
                AppUsageSlice(appName: "Safari", bundleId: "com.apple.Safari", durationSeconds: 300, windowTitles: ["Apple Docs"])
            ]
        )

        let exporter = ObsidianExporter()
        let markdown = exporter.exportDayToMarkdown(date: Date(timeIntervalSince1970: 1700000000), cards: [card1])

        #expect(markdown.contains("---"))
        #expect(markdown.contains("date:"))
        #expect(markdown.contains("Development:"))
        #expect(markdown.contains("> [!info] Разработка ядра MyDay"))
        #expect(markdown.contains("Xcode (66%)"))
        #expect(markdown.contains("#swift"))
    }

    // MARK: - Database Manager Tests

    @Test("DatabaseManager persists and fetches timeline cards")
    func testDatabaseSaveAndFetch() throws {
        let db = DatabaseManager.shared
        let testId = UUID()
        let now = Date()

        let card = TimelineCard(
            id: testId,
            startTime: now,
            endTime: now.addingTimeInterval(600),
            title: "Test Database Card",
            summary: "Verified SQLite persistence",
            category: .research,
            tags: ["test", "sqlite"],
            appUsages: [
                AppUsageSlice(appName: "Terminal", bundleId: "com.apple.Terminal", durationSeconds: 600)
            ],
            isAIAnalyzed: true
        )

        db.saveCard(card)

        let cards = db.fetchCards(for: now)
        let found = cards.first(where: { $0.id == testId })

        #expect(found != nil)
        #expect(found?.title == "Test Database Card")
        #expect(found?.category == .research)
        #expect(found?.isAIAnalyzed == true)

        // Cleanup
        db.deleteCard(id: testId)
        let cardsAfter = db.fetchCards(for: now)
        #expect(cardsAfter.first(where: { $0.id == testId }) == nil)
    }

    // MARK: - Activity Category Tests

    @Test("ActivityCategory matching heuristics")
    func testCategoryMatching() throws {
        #expect(ActivityCategory.match(from: "Xcode") == .development)
        #expect(ActivityCategory.match(from: "Visual Studio Code") == .development)
        #expect(ActivityCategory.match(from: "Safari") == .research)
        #expect(ActivityCategory.match(from: "Telegram") == .communication)
        #expect(ActivityCategory.match(from: "Figma") == .design)
        #expect(ActivityCategory.match(from: "Notes") == .writing)
        #expect(ActivityCategory.match(from: "YouTube") == .entertainment)
    }

    // MARK: - LM Studio Client Live Test

    @Test("LMStudioClient communicates with local LM Studio instance")
    func testLMStudioLiveCall() async throws {
        let client = LMStudioClient.shared
        do {
            let models = try await client.fetchAvailableModels(baseURL: "http://127.0.0.1:1234/v1")
            #expect(!models.isEmpty)
            #expect(models.contains("qwen3-vl-4b-instruct"))

            let prompt = PromptTemplates.buildUserPrompt(
                timeRangeString: "11:00 – 11:15 (15 min)",
                appUsages: [
                    AppUsageSlice(appName: "Xcode", bundleId: "com.apple.dt.Xcode", durationSeconds: 600, windowTitles: ["MyDayApp.swift"]),
                    AppUsageSlice(appName: "Terminal", bundleId: "com.apple.Terminal", durationSeconds: 300, windowTitles: ["swift test"])
                ],
                ocrKeywords: ["ScreenCaptureKit", "Vision", "AVAssetWriter"],
                keyTextLines: ["func captureMainDisplay()", "let card = TimelineCard(...)"]
            )

            let response = try await client.analyzeActivity(
                baseURL: "http://127.0.0.1:1234/v1",
                model: "qwen3-vl-4b-instruct",
                userPrompt: prompt,
                isVisionMode: false
            )

            #expect(!response.title.isEmpty)
            #expect(!response.summary.isEmpty)
            print("Live LM Studio analysis test succeeded:")
            print("Title: \(response.title)")
            print("Summary: \(response.summary)")
            print("Category: \(response.category)")
            print("Tags: \(response.tags)")
        } catch {
            print("Live LM Studio test skipped or failed: \(error)")
        }
    }

    // MARK: - Remote Desktop & OCR Category Tests

    @Test("Remote Desktop & Virtual Machine identification")
    func testRemoteDesktopDetection() throws {
        #expect(WindowTracker.isRemoteDesktopOrVM(appName: "Windows App", bundleId: "com.microsoft.rdc.macos"))
        #expect(WindowTracker.isRemoteDesktopOrVM(appName: "Microsoft Remote Desktop", bundleId: "com.microsoft.rdc.application-client"))
        #expect(WindowTracker.isRemoteDesktopOrVM(appName: "AnyDesk", bundleId: "com.philandro.anydesk"))
        #expect(WindowTracker.isRemoteDesktopOrVM(appName: "Parallels Desktop", bundleId: "com.parallels.desktop.console"))
        #expect(WindowTracker.isRemoteDesktopOrVM(appName: "Citrix Workspace", bundleId: "com.citrix.receiver.icaviewer.mac"))
        #expect(!WindowTracker.isRemoteDesktopOrVM(appName: "Safari", bundleId: "com.apple.Safari"))
        #expect(!WindowTracker.isRemoteDesktopOrVM(appName: "Xcode", bundleId: "com.apple.dt.Xcode"))
    }

    @Test("OCR-assisted ActivityCategory classification for remote sessions")
    func testRemoteDesktopCategoryMatching() throws {
        // Windows App with code keywords
        let catDev = ActivityCategory.match(from: "Windows App", ocrKeywords: ["SQL", "Query", "SELECT", "Code"])
        #expect(catDev == .development)

        // Windows App with document/report keywords
        let catWrite = ActivityCategory.match(from: "Windows App", ocrKeywords: ["Excel", "Отчет", "Таблица"])
        #expect(catWrite == .writing)

        // Windows App with server administration keywords -> .work (NEVER .utility / "Система")
        let catWork = ActivityCategory.match(from: "Windows App", ocrKeywords: ["Server", "PowerShell", "Admin"])
        #expect(catWork == .work)

        // Windows App without keywords defaults to Work (productive work) instead of Utility or Other
        let catDefault = ActivityCategory.match(from: "Windows App", ocrKeywords: [])
        #expect(catDefault == .work)
    }

    @Test("UnfinishedTasksExtractor extracts actionable items for remote sessions")
    func testUnfinishedTasksExtractorRemote() throws {
        let extractor = UnfinishedTasksExtractor.shared
        let card = TimelineCard(
            startTime: Date(timeIntervalSince1970: 1700000000),
            endTime: Date(timeIntervalSince1970: 1700001800),
            title: "Работа в Windows App",
            summary: "Удаленная сессия",
            category: .development,
            tags: ["windows app", "rdp"],
            appUsages: [
                AppUsageSlice(appName: "Windows App", bundleId: "com.microsoft.rdc.macos", durationSeconds: 1500, windowTitles: ["wab2.bspb.ru"])
            ],
            ocrKeywords: ["GeekHub", "Вебинар", "API"]
        )

        let tasks = extractor.extractTasks(from: [card])
        #expect(!tasks.isEmpty)
        #expect(tasks.contains(where: { $0.appName == "Windows App" }))
    }

    @Test("Smart Heuristic Card Generation (Native Mode without AI)")
    func testSmartHeuristicCardGeneration() throws {
        // 1. YouTube video in Zen Browser
        let zenSlice = AppUsageSlice(
            appName: "Zen",
            bundleId: "app.zen-browser.zen",
            durationSeconds: 600,
            windowTitles: ["Hyperoptimized Engineer 2026 - YouTube", "Zen Browser"]
        )
        let youtubeCard = BatchAggregator.generateSmartHeuristicCard(
            primaryApp: "Zen",
            appSlices: [zenSlice],
            ocrKeywords: ["Hyperoptimized", "Engineer"],
            keyTextLines: ["YouTube", "Hyperoptimized Engineer 2026"]
        )
        #expect(youtubeCard.category == .entertainment)
        #expect(youtubeCard.title.contains("Hyperoptimized Engineer 2026"))

        // 2. Database session in Windows App
        let rdpSlice = AppUsageSlice(
            appName: "Windows App",
            bundleId: "com.microsoft.rdc.macos",
            durationSeconds: 1200,
            windowTitles: ["wab2.bspb.ru"]
        )
        let dbCard = BatchAggregator.generateSmartHeuristicCard(
            primaryApp: "Windows App",
            appSlices: [rdpSlice],
            ocrKeywords: ["DBeaver", "PostgreSQL", "SELECT", "naumen-prod"],
            keyTextLines: ["SELECT version();", "DBeaver 24.3"]
        )
        #expect(dbCard.category == .work)
        #expect(dbCard.title.contains("DBeaver") || dbCard.title.contains("базами данных"))

        // 3. Coding session in Xcode
        let xcodeSlice = AppUsageSlice(
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            durationSeconds: 900,
            windowTitles: ["MyDay — DateNavigatorView.swift"]
        )
        let codeCard = BatchAggregator.generateSmartHeuristicCard(
            primaryApp: "Xcode",
            appSlices: [xcodeSlice],
            ocrKeywords: ["struct", "View", "body"],
            keyTextLines: ["public struct DateNavigatorView: View"]
        )
        #expect(codeCard.category == .development)
        #expect(codeCard.title.contains("DateNavigatorView.swift"))

        // 4. Communication in Telegram
        let tgSlice = AppUsageSlice(
            appName: "Telegram",
            bundleId: "ru.keepcoder.Telegram",
            durationSeconds: 300,
            windowTitles: ["Telegram @ Мишаня"]
        )
        let chatCard = BatchAggregator.generateSmartHeuristicCard(
            primaryApp: "Telegram",
            appSlices: [tgSlice],
            ocrKeywords: [],
            keyTextLines: []
        )
        #expect(chatCard.category == .communication)
        #expect(chatCard.title.contains("Мишаня"))
    }

    @Test("EngineMode Settings Serialization")
    func testEngineModeSerialization() throws {
        let settings = UserSettings(engineMode: .native)
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: encoded)
        #expect(decoded.engineMode == .native)

        let aiSettings = UserSettings(engineMode: .lmStudio)
        let aiEncoded = try JSONEncoder().encode(aiSettings)
        let aiDecoded = try JSONDecoder().decode(UserSettings.self, from: aiEncoded)
        #expect(aiDecoded.engineMode == .lmStudio)
    }

    @Test("Storage Limit Setting and Auto-Cleanup calculation")
    func testStorageLimitSetting() throws {
        // Serialization of maxStorageGB & cleanupPolicy
        let defaultSettings = UserSettings()
        #expect(defaultSettings.maxStorageGB == 5.0)
        #expect(defaultSettings.cleanupPolicy == .bySize)

        let customSettings = UserSettings(maxStorageGB: 8.0, cleanupPolicy: .byDays)
        let encoded = try JSONEncoder().encode(customSettings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: encoded)
        #expect(decoded.maxStorageGB == 8.0)
        #expect(decoded.cleanupPolicy == .byDays)

        // Storage size calculation returns non-negative value and formatted string
        let storage = TimelapseStorage.shared
        let totalSize = storage.calculateTotalFramesSize()
        #expect(totalSize >= 0)

        let formatted = storage.calculateFormattedFramesSize()
        #expect(!formatted.isEmpty)

        // Test runCleanup across all policies without crashing
        storage.runCleanup(policy: .bySize, retentionDays: 7, maxStorageGB: 50.0)
        storage.runCleanup(policy: .byDays, retentionDays: 30, maxStorageGB: 50.0)
        storage.runCleanup(policy: .byBoth, retentionDays: 30, maxStorageGB: 50.0)
    }
}
