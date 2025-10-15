//
//  AIExplainerAgent.swift
//  InternalFlow
//
//  Created by Ruizhe Zheng on 10/15/25.
//


//
//  AIExplainerAgent.swift
//  InternalFlow
//
//  Purpose: Send the selected event + current user emotion to OpenAI (gpt-4o)
//  and get a short, friendly explanation of *why* this recommendation makes sense.
//
//  How to use:
//  let agent = AIExplainerAgent(apiKey: "<YOUR_OPENAI_API_KEY>")
//  let text = try await agent.explainRecommendation(event: event, userEmotion: .uneasy)
//  // show `text` in UI
//

import Foundation

// MARK: - Agent

public final class AIExplainerAgent {
    struct Config {
        public var model: String = "gpt-4o"     // 4o-model as requested
        public var temperature: Double = 0.4
        public var maxTokens: Int? = 300        // optional cap for safety

        public init(model: String = "gpt-4o", temperature: Double = 0.4, maxTokens: Int? = 300) {
            self.model = model
            self.temperature = temperature
            self.maxTokens = maxTokens
        }
    }

    private let apiKey: String
    private let config: Config
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    init(apiKey: String, config: Config = .init()) {
        self.apiKey = apiKey
        self.config = config
    }

    /// Call this right after你的算法挑出“今天要做”的那条 Event。
    /// - Returns: A short, motivational explanation for the user.
    func explainRecommendation(event: Event, userEmotion: Emotion) async throws -> String {
        let messages = buildMessages(event: event, emotion: userEmotion)
        let body = ChatCompletionsRequest(
            model: config.model,
            temperature: config.temperature,
            max_tokens: config.maxTokens,
            messages: messages
        )

        let data = try JSONEncoder().encode(body)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = data

        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AgentError.network("Invalid response")
        }
        guard (200...299).contains(http.statusCode) else {
            let apiErr = String(data: respData, encoding: .utf8) ?? "<no body>"
            throw AgentError.api("HTTP \(http.statusCode): \(apiErr)")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: respData)
        if let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        throw AgentError.api("Empty completion")
    }
}

// MARK: - Prompt Construction

private extension AIExplainerAgent {
    func buildMessages(event: Event, emotion: Emotion) -> [ChatMessage] {
        // Format deadline to a friendly date like "Oct 15, 2025"
        let df = DateFormatter()
        df.locale = .current
        df.dateStyle = .medium
        df.timeStyle = .none

        let payload = SerializableEvent(
            name: event.name,
            deadline: df.string(from: event.deadline),
            // Ensure we keep one decimal place, same as UI stepper style
            estimatedHours: String(format: "%.1f", event.estimatetimes),
            difficulty: event.level // "Easy"/"Medium"/"Hard"
        )

        // System style: short, warm, concrete, and emotion-aware.
        let system = """
        You are a concise, supportive study coach. Explain in 1–3 sentences \
        why the suggested task is a good choice *right now* given the user's current emotion, \
        the deadline urgency, the time needed, and the difficulty. \
        Be empathetic but direct; include one actionable next step (e.g., “start with a 10-minute focus block”). \
        Output plain text only (no bullets, no markdown).
        """

        // Optional note to let the model reference the same heuristics our backend used.
        // This helps the model stay aligned with why the algorithm picked this item.
        let heuristics = """
        Heuristics used by the backend:
        - Prioritize earlier deadlines.
        - Adjust by emotion/difficulty preference (examples):
          Alert → Hard > Medium > Easy
          Focused → Medium > Hard > Easy
          Anxious → Easy > Medium > Hard
          Distracted → Easy > Medium > Hard
        """

        // Package all info the model needs.
        let user = """
        CurrentEmotion: \(emotion.rawValue)
        RecommendedEvent:
        {
          "name": "\(payload.name)",
          "deadline": "\(payload.deadline)",
          "estimatedHours": "\(payload.estimatedHours)",
          "difficulty": "\(payload.difficulty)"
        }

        \(heuristics)
        """

        return [
            .init(role: "system", content: system),
            .init(role: "user", content: user)
        ]
    }
}

// MARK: - Lightweight DTOs

/// Keep a stable, serializable shape for the model.
private struct SerializableEvent: Codable {
    let name: String
    let deadline: String
    let estimatedHours: String
    let difficulty: String
}

// MARK: - OpenAI Wire Models

private struct ChatCompletionsRequest: Codable {
    let model: String
    let temperature: Double?
    let max_tokens: Int?
    let messages: [ChatMessage]
}

private struct ChatMessage: Codable {
    let role: String
    let content: String?
}

private struct ChatCompletionsResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String?
        }
        let index: Int?
        let message: Message
        let finish_reason: String?
    }
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    // usage omitted, add if you want token accounting
}

// MARK: - Errors

public enum AgentError: Error, LocalizedError {
    case network(String)
    case api(String)

    public var errorDescription: String? {
        switch self {
        case .network(let s): return "Network error: \(s)"
        case .api(let s):     return "API error: \(s)"
        }
    }
}
