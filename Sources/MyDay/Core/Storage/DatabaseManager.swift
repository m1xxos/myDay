import Foundation
import SQLite3

public final class DatabaseManager: @unchecked Sendable {
    public static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.myday.database.queue", qos: .userInitiated)

    public init() {
        openDatabase()
        createTables()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    private func getDatabaseURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let myDayDir = appSupport.appendingPathComponent("MyDay", isDirectory: true)

        if !fileManager.fileExists(atPath: myDayDir.path) {
            try? fileManager.createDirectory(at: myDayDir, withIntermediateDirectories: true)
        }

        return myDayDir.appendingPathComponent("myday.sqlite")
    }

    private func openDatabase() {
        let dbURL = getDatabaseURL()
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("[DatabaseManager] Error opening database at \(dbURL.path)")
        } else {
            // Enable WAL mode for high performance concurrency
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
            sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        }
    }

    private func createTables() {
        let createCardsTable = """
        CREATE TABLE IF NOT EXISTS timeline_cards (
            id TEXT PRIMARY KEY,
            start_time REAL NOT NULL,
            end_time REAL NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            category TEXT NOT NULL,
            tags TEXT,
            app_usages TEXT,
            keyframe_path TEXT,
            timelapse_video_path TEXT,
            frame_count INTEGER DEFAULT 0,
            is_ai_analyzed INTEGER DEFAULT 0,
            ocr_keywords TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_timeline_cards_start ON timeline_cards(start_time);
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createCardsTable, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("[DatabaseManager] Error creating tables: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - CRUD Operations

    public func saveCard(_ card: TimelineCard) {
        queue.sync {
            let sql = """
            INSERT OR REPLACE INTO timeline_cards (
                id, start_time, end_time, title, summary, category, tags,
                app_usages, keyframe_path, timelapse_video_path, frame_count,
                is_ai_analyzed, ocr_keywords
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let tagsJson = (try? JSONEncoder().encode(card.tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let usagesJson = (try? JSONEncoder().encode(card.appUsages)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let ocrJson = (try? JSONEncoder().encode(card.ocrKeywords)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

            sqlite3_bind_text(stmt, 1, card.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, card.startTime.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, card.endTime.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 4, card.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, card.summary, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, card.category.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 7, tagsJson, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 8, usagesJson, -1, SQLITE_TRANSIENT)

            if let keyframe = card.keyframePath {
                sqlite3_bind_text(stmt, 9, keyframe, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 9)
            }

            if let video = card.timelapseVideoPath {
                sqlite3_bind_text(stmt, 10, video, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }

            sqlite3_bind_int(stmt, 11, Int32(card.frameCount))
            sqlite3_bind_int(stmt, 12, card.isAIAnalyzed ? 1 : 0)
            sqlite3_bind_text(stmt, 13, ocrJson, -1, SQLITE_TRANSIENT)

            sqlite3_step(stmt)
        }
    }

    public func fetchCards(for date: Date) -> [TimelineCard] {
        queue.sync {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date).timeIntervalSince1970
            let endOfDay = (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date).timeIntervalSince1970

            let sql = """
            SELECT id, start_time, end_time, title, summary, category, tags,
                   app_usages, keyframe_path, timelapse_video_path, frame_count,
                   is_ai_analyzed, ocr_keywords
            FROM timeline_cards
            WHERE start_time >= ? AND start_time < ?
            ORDER BY start_time ASC;
            """

            var stmt: OpaquePointer?
            var cards: [TimelineCard] = []

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return cards }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, startOfDay)
            sqlite3_bind_double(stmt, 2, endOfDay)

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let card = parseCard(from: stmt) {
                    cards.append(card)
                }
            }

            return cards
        }
    }

    public func fetchAllCards(limit: Int = 100) -> [TimelineCard] {
        queue.sync {
            let sql = """
            SELECT id, start_time, end_time, title, summary, category, tags,
                   app_usages, keyframe_path, timelapse_video_path, frame_count,
                   is_ai_analyzed, ocr_keywords
            FROM timeline_cards
            ORDER BY start_time DESC
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            var cards: [TimelineCard] = []

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return cards }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let card = parseCard(from: stmt) {
                    cards.append(card)
                }
            }

            return cards
        }
    }

    public func fetchActiveDays(inMonth date: Date) -> Set<Int> {
        queue.sync {
            let calendar = Calendar.current
            guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
            let start = interval.start.timeIntervalSince1970
            let end = interval.end.timeIntervalSince1970

            let sql = """
            SELECT start_time
            FROM timeline_cards
            WHERE start_time >= ? AND start_time < ?;
            """

            var stmt: OpaquePointer?
            var days = Set<Int>()

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return days }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, start)
            sqlite3_bind_double(stmt, 2, end)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let epoch = sqlite3_column_double(stmt, 0)
                let cardDate = Date(timeIntervalSince1970: epoch)
                let day = calendar.component(.day, from: cardDate)
                days.insert(day)
            }

            return days
        }
    }

    public func deleteCard(id: UUID) {
        queue.sync {
            let sql = "DELETE FROM timeline_cards WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
    }

    private func parseCard(from stmt: OpaquePointer?) -> TimelineCard? {
        guard let stmt = stmt else { return nil }

        guard let idStr = sqlite3_column_text(stmt, 0).flatMap({ String(cString: $0) }),
              let id = UUID(uuidString: idStr) else { return nil }

        let startEpoch = sqlite3_column_double(stmt, 1)
        let endEpoch = sqlite3_column_double(stmt, 2)
        let title = sqlite3_column_text(stmt, 3).flatMap({ String(cString: $0) }) ?? "Activity"
        let summary = sqlite3_column_text(stmt, 4).flatMap({ String(cString: $0) }) ?? ""
        let catStr = sqlite3_column_text(stmt, 5).flatMap({ String(cString: $0) }) ?? "Other"
        let category = ActivityCategory.match(from: catStr)

        let tagsJson = sqlite3_column_text(stmt, 6).flatMap({ String(cString: $0) }) ?? "[]"
        let usagesJson = sqlite3_column_text(stmt, 7).flatMap({ String(cString: $0) }) ?? "[]"
        let keyframe = sqlite3_column_text(stmt, 8).flatMap({ String(cString: $0) })
        let video = sqlite3_column_text(stmt, 9).flatMap({ String(cString: $0) })
        let frameCount = Int(sqlite3_column_int(stmt, 10))
        let isAnalyzed = sqlite3_column_int(stmt, 11) == 1
        let ocrJson = sqlite3_column_text(stmt, 12).flatMap({ String(cString: $0) }) ?? "[]"

        let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsJson.utf8))) ?? []
        let appUsages = (try? JSONDecoder().decode([AppUsageSlice].self, from: Data(usagesJson.utf8))) ?? []
        let ocrKeywords = (try? JSONDecoder().decode([String].self, from: Data(ocrJson.utf8))) ?? []

        return TimelineCard(
            id: id,
            startTime: Date(timeIntervalSince1970: startEpoch),
            endTime: Date(timeIntervalSince1970: endEpoch),
            title: title,
            summary: summary,
            category: category,
            tags: tags,
            appUsages: appUsages,
            keyframePath: keyframe,
            timelapseVideoPath: video,
            frameCount: frameCount,
            isAIAnalyzed: isAnalyzed,
            ocrKeywords: ocrKeywords
        )
    }
}

// Helpers for SQLite string binding
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
