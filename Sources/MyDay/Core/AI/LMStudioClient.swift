import Foundation
import AppKit

public final class LMStudioClient: @unchecked Sendable {
    public static let shared = LMStudioClient()

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }

    // MARK: - Models Discovery

    public func fetchAvailableModels(baseURL: String = "http://127.0.0.1:1234/v1") async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/models") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct ModelListResponse: Codable {
            struct ModelEntry: Codable {
                let id: String
            }
            let data: [ModelEntry]
        }

        let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
        return decoded.data.map { $0.id }
    }

    // MARK: - Analyze Activity

    public func analyzeActivity(
        baseURL: String = "http://127.0.0.1:1234/v1",
        model: String,
        userPrompt: String,
        keyframePath: String? = nil,
        isVisionMode: Bool = false
    ) async throws -> AIActivityResponse {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw URLError(.badURL)
        }

        var messages: [[String: Any]] = [
            ["role": "system", "content": PromptTemplates.systemPrompt]
        ]

        if isVisionMode, let keyframePath = keyframePath,
           let image = NSImage(contentsOfFile: keyframePath),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.65]) {
            let base64 = jpeg.base64EncodedString()
            let contentArray: [[String: Any]] = [
                ["type": "text", "text": userPrompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
            ]
            messages.append(["role": "user", "content": contentArray])
        } else {
            messages.append(["role": "user", "content": userPrompt])
        }

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": 500
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "LMStudioClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "Server response error: \(bodyStr)"])
        }

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String?
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let rawContent = chatResponse.choices.first?.message.content else {
            throw NSError(domain: "LMStudioClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content in model response"])
        }

        let cleaned = cleanJSONString(rawContent)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw NSError(domain: "LMStudioClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert string to JSON data"])
        }

        do {
            var aiResponse = try JSONDecoder().decode(AIActivityResponse.self, from: jsonData)
            if aiResponse.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                aiResponse = AIActivityResponse(
                    is_continuation: aiResponse.is_continuation,
                    title: aiResponse.title,
                    summary: "Работа над задачами: \(aiResponse.title)",
                    category: aiResponse.category,
                    tags: aiResponse.tags
                )
            }
            return aiResponse
        } catch {
            // Attempt to extract title/summary from loose JSON or fallback
            return try parseFallbackJSON(from: cleaned)
        }
    }

    private func cleanJSONString(_ raw: String) -> String {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip ```json and ```
        if let startRange = str.range(of: "```json") {
            str = String(str[startRange.upperBound...])
        } else if let startRange = str.range(of: "```") {
            str = String(str[startRange.upperBound...])
        }

        if let endRange = str.range(of: "```", options: .backwards) {
            str = String(str[..<endRange.lowerBound])
        }

        str = str.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find outer { and }
        if let firstBrace = str.firstIndex(of: "{"),
           let lastBrace = str.lastIndex(of: "}") {
            str = String(str[firstBrace...lastBrace])
        }

        return str
    }

    private func parseFallbackJSON(from text: String) throws -> AIActivityResponse {
        // Fallback heuristic if local model missed a quote or tag array
        if let dict = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] {
            let isCont = dict["is_continuation"] as? Bool ?? false
            let title = dict["title"] as? String ?? "Activity"
            var summary = (dict["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty {
                summary = "Активность: \(title)"
            }
            let cat = dict["category"] as? String ?? "Other"
            let tags = dict["tags"] as? [String] ?? []
            return AIActivityResponse(is_continuation: isCont, title: title, summary: summary, category: cat, tags: tags)
        }

        throw NSError(domain: "LMStudioClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Could not parse JSON: \(text)"])
    }

    // MARK: - Unfinished Tasks Extraction

    public func extractUnfinishedTasks(
        baseURL: String = "http://127.0.0.1:1234/v1",
        model: String,
        cards: [TimelineCard]
    ) async throws -> [UnfinishedTask] {
        guard !cards.isEmpty else { return [] }
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw URLError(.badURL)
        }

        let userPrompt = PromptTemplates.buildUnfinishedTasksPrompt(cards: cards)
        let messages: [[String: Any]] = [
            ["role": "system", "content": PromptTemplates.systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": 500
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "LMStudioClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "Server response error: \(bodyStr)"])
        }

        struct ChatResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String?
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let rawContent = chatResponse.choices.first?.message.content else {
            throw NSError(domain: "LMStudioClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content in model response"])
        }

        let cleaned = cleanJSONString(rawContent)
        guard let jsonData = cleaned.data(using: .utf8) else {
            throw NSError(domain: "LMStudioClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert string to JSON data"])
        }

        do {
            let parsed = try JSONDecoder().decode(AIUnfinishedTasksResponse.self, from: jsonData)
            return parsed.tasks.compactMap { item in
                let trimmed = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return UnfinishedTask(
                    title: trimmed,
                    appName: item.app_name.isEmpty ? "Mac" : item.app_name,
                    category: ActivityCategory.match(from: item.category)
                )
            }
        } catch {
            // Loose JSON fallback
            if let dict = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any],
               let taskList = dict["tasks"] as? [[String: Any]] {
                return taskList.compactMap { dictItem in
                    let title = (dictItem["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return nil }
                    let app = dictItem["app_name"] as? String ?? "Mac"
                    let cat = dictItem["category"] as? String ?? "Other"
                    return UnfinishedTask(
                        title: title,
                        appName: app,
                        category: ActivityCategory.match(from: cat)
                    )
                }
            }
            throw error
        }
    }
}

