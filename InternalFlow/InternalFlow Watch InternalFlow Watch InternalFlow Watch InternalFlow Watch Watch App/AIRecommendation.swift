//
//  AIRecommendation.swift
//  InternalFlow
//
//  Created by Ruizhe Zheng on 9/18/25.
//

import Foundation

// ========================= Public-ish Models (internal) =========================

struct AIRecommendation: Codable {
    let chosenEventId: UUID
    let reason: String
}

struct AIRankingItem: Codable {
    let eventId: UUID
    let score: Double?
    let reason: String
}

struct AIRankingResult: Codable {
    let chosen: AIRecommendation
    let ranking: [AIRankingItem]
}

struct AIContext: Codable {
    let emotion: String          // e.g., "anxious", "calm", "motivated"
    let heartRateBPM: Double?
    let hrvSDNNms: Double?

    init(emotion: String, heartRateBPM: Double? = nil, hrvSDNNms: Double? = nil) {
        self.emotion = emotion
        self.heartRateBPM = heartRateBPM
        self.hrvSDNNms = hrvSDNNms
    }
}

// ========================= Recommender (no Event dependency) =========================

enum AIRecommender {

    // ---- Keep the same name but accept [Any] so it compiles in all targets ----
    @discardableResult
    static func recommend(
        events: [Any],
        ctx: AIContext,
        apiKey: String,
        model: String = "o4-mini",
        timeout: TimeInterval = 20
    ) async throws -> AIRecommendation {
        if let hybrid = try? await recommendHybrid(
            events: events, ctx: ctx, apiKey: apiKey, model: model, timeout: timeout, ruleTopK: 5
        ) {
            return hybrid.chosen
        }
        let res = try await rankTopN(events: events, ctx: ctx, apiKey: apiKey, model: model, timeout: timeout, topN: nil)
        return res.chosen
    }

    static func rankTopN(
        events: [Any],
        ctx: AIContext,
        apiKey: String,
        model: String = "o4-mini",
        timeout: TimeInterval = 20,
        topN: Int? = nil
    ) async throws -> AIRankingResult {

        let candidates = events
        guard !candidates.isEmpty else {
            throw err("No events to rank", code: -10)
        }

        // Down-convert to plain JSON objects for the model
        let reduced: [[String: Any]] = candidates.compactMap { any in
            guard let id = extractId(fromAny: any) else { return nil }
            return [
                "id": id.uuidString,
                "name": extractName(fromAny: any) ?? "Untitled",
                "deadline": extractDeadline(fromAny: any).map(iso8601) as Any,
                "estimatedHours": extractEstimatedHours(fromAny: any) as Any,
                "difficulty": extractDifficultyRaw(fromAny: any) as Any
            ]
        }

        let system = """
        You are a rigorous task recommender for a watchOS focus app.
        Return STRICT JSON ONLY, no code fences, no extra text.
        JSON shape:
        {
          "chosen": { "chosenEventId": "<UUID>", "reason": "<short>" },
          "ranking": [
            { "eventId": "<UUID>", "score": <number|null>, "reason": "<short>" }
          ]
        }
        Rules:
        - Choose ONE best event to start now.
        - Prefer: near deadlines, fit to emotion/physiology, reasonable difficulty,
          and quick wins when stressed.
        - All ids must be from candidates.
        """

        var userDict: [String: Any] = [
            "now": iso8601(Date()),
            "context": [
                "emotion": ctx.emotion,
                "heartRateBPM": ctx.heartRateBPM as Any,
                "hrvSDNNms": ctx.hrvSDNNms as Any
            ],
            "candidates": reduced
        ]
        if let n = topN { userDict["topN_limit"] = n }

        let user = """
        Rank these tasks and select one. Keep JSON strictly valid.
        \(json(userDict))
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ],
            "temperature": 0.2,
            "seed": 7
        ]

        let data = try await postJson(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            apiKey: apiKey,
            body: body,
            timeout: timeout
        )

        let (content, _) = try parseChatCompletionsContent(data)
        let jsonBlob = try extractJson(content)

        let obj = try JSONSerialization.jsonObject(with: jsonBlob) as! [String: Any]
        guard
            let chosen = obj["chosen"] as? [String: Any],
            let idStr = chosen["chosenEventId"] as? String,
            let cid = UUID(uuidString: idStr),
            let reason = chosen["reason"] as? String
        else {
            throw err("Invalid chosen JSON", code: -11)
        }

        var ranking: [AIRankingItem] = []
        if let arr = obj["ranking"] as? [[String: Any]] {
            for it in arr {
                if let id = (it["eventId"] as? String).flatMap(UUID.init(uuidString:)) {
                    let s = it["score"] as? Double
                    let r = (it["reason"] as? String) ?? ""
                    ranking.append(.init(eventId: id, score: s, reason: r))
                }
            }
        }

        return AIRankingResult(chosen: .init(chosenEventId: cid, reason: reason), ranking: ranking)
    }

    static func recommendHybrid(
        events: [Any],
        ctx: AIContext,
        apiKey: String,
        model: String = "o4-mini",
        timeout: TimeInterval = 20,
        ruleTopK: Int = 5
    ) async throws -> AIRankingResult? {
        guard !events.isEmpty else { return nil }

        let now = Date()
        let scored: [(Int, Double)] = events.enumerated().map { (idx, any) in
            let urgency = extractDeadline(fromAny: any).map { urgencyScore(deadline: $0, now: now) } ?? 0.2
            let quick   = extractEstimatedHours(fromAny: any).map { quickWinsScore(hours: $0) } ?? 0.3
            let diff    = difficultyFitScore(raw: extractDifficultyRaw(fromAny: any), emotion: emotionBucket(ctx.emotion))
            let boost   = extractDeadline(fromAny: any).map { specialDateBoost(deadline: $0, now: now) } ?? 0
            let s = 0.6 * urgency + 0.25 * diff + 0.15 * quick + boost
            return (idx, s)
        }
        .sorted { $0.1 > $1.1 }

        let top: [Any] = Array(scored.prefix(max(1, ruleTopK))).map { events[$0.0] }
        return try await rankTopN(events: top, ctx: ctx, apiKey: apiKey, model: model, timeout: timeout, topN: nil)
    }

    // ========================= HTTP & Parse =========================

    private static func postJson(url: URL, apiKey: String, body: [String: Any], timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? "<no body>"
            throw err("OpenAI error: \(txt)", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    private static func parseChatCompletionsContent(_ data: Data) throws -> (String, String?) {
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard
            let choices = root["choices"] as? [[String: Any]],
            let msg = choices.first?["message"] as? [String: Any],
            let content = msg["content"] as? String
        else { throw err("Malformed response", code: -20) }
        let finish = choices.first?["finish_reason"] as? String
        return (content, finish)
    }

    /// Extract the first valid JSON object from a string.
    private static func extractJson(_ content: String) throws -> Data {
        if let data = content.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        if let range = firstBalancedJsonRange(in: content) {
            let sub = String(content[range])
            if let data = sub.data(using: .utf8),
               (try? JSONSerialization.jsonObject(with: data)) != nil {
                return data
            }
        }
        throw err("Model did not return valid JSON", code: -21)
    }

    private static func firstBalancedJsonRange(in s: String) -> ClosedRange<String.Index>? {
        var stack = 0
        var start: String.Index?
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "{" {
                if stack == 0 { start = i }
                stack += 1
            } else if ch == "}" {
                stack -= 1
                if stack == 0, let st = start { return st...i }
            }
            i = s.index(after: i)
        }
        return nil
    }

    // ========================= Local scoring helpers =========================

    private static func iso8601(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    private static func json(_ dict: [String: Any]) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: dict, options: [.withoutEscapingSlashes]), encoding: .utf8)) ?? "{}"
    }

    private static func urgencyScore(deadline: Date, now: Date) -> Double {
        let dt = deadline.timeIntervalSince(now) / 86_400.0
        if dt <= 0 { return 1.0 }
        let horizon = 14.0
        let clamped = max(0, min(1, 1 - dt / horizon))
        return pow(clamped, 0.7)
    }

    private enum EmotionBucket { case stressed, neutral, energized }
    private static func emotionBucket(_ s: String) -> EmotionBucket {
        let lower = s.lowercased()
        if ["anxious","uneasy","tired","distracted","stressed","overwhelmed"].contains(where: { lower.contains($0) }) {
            return .stressed
        }
        if ["alert","focused","motivated","energetic","energized","happy"].contains(where: { lower.contains($0) }) {
            return .energized
        }
        return .neutral
    }

    private static func difficultyFitScore(raw: String?, emotion: EmotionBucket) -> Double {
        let d = (raw ?? "").lowercased()
        let isEasy = d.contains("easy") || d.contains("low") || d.contains("simple")
        let isHard = d.contains("hard") || d.contains("high") || d.contains("difficult")
        switch emotion {
        case .stressed:   return isEasy ? 1.0 : (isHard ? 0.25 : 0.6)
        case .neutral:    return isEasy ? 0.6 : (isHard ? 0.6  : 1.0)
        case .energized:  return isHard ? 1.0 : (isEasy ? 0.25 : 0.6)
        }
    }

    private static func quickWinsScore(hours: Double) -> Double {
        if hours <= 0.5 { return 1.0 }
        if hours <= 1.0 { return 0.6 }
        return 0.2
    }

    private static func specialDateBoost(deadline: Date, now: Date) -> Double {
        let cal = Calendar.current
        if cal.isDate(deadline, inSameDayAs: now) { return 0.2 }
        if deadline < now { return 0.3 }
        return 0
    }

    // ========================= Reflection bridges (Any) =========================

    private static func extractId(fromAny any: Any) -> UUID? {
        let m = Mirror(reflecting: any)
        for c in m.children where c.label == "id" {
            if let u = c.value as? UUID { return u }
            if let s = c.value as? String, let u = UUID(uuidString: s) { return u }
        }
        return nil
    }

    private static func extractName(fromAny any: Any) -> String? {
        let m = Mirror(reflecting: any)
        for c in m.children {
            if c.label == "name", let s = c.value as? String { return s }
            if c.label == "title", let s = c.value as? String { return s }
        }
        return nil
    }

    private static func extractDeadline(fromAny any: Any) -> Date? {
        let m = Mirror(reflecting: any)
        for c in m.children {
            if c.label == "deadline", let d = c.value as? Date { return d }
            if c.label == "dueDate",  let d = c.value as? Date { return d }
            if c.label == "date",     let d = c.value as? Date { return d }
        }
        return nil
    }

    private static func extractEstimatedHours(fromAny any: Any) -> Double? {
        let m = Mirror(reflecting: any)
        for c in m.children {
            guard let key = c.label else { continue }
            if ["estimatedHours","estimateHours","estimated","estimate","estimatetimes","estimateTime"].contains(key) {
                if let d = c.value as? Double { return d }
                if let i = c.value as? Int { return Double(i) }
                if let s = c.value as? String, let d = Double(s) { return d }
            }
        }
        return nil
    }

    private static func extractDifficultyRaw(fromAny any: Any) -> String? {
        let m = Mirror(reflecting: any)
        for c in m.children {
            if ["difficulty","level"].contains(c.label ?? "") {
                if let s = c.value as? String { return s }
                if let r = c.value as? CustomStringConvertible { return r.description }
                return "\(c.value)"
            }
        }
        return nil
    }

    // ========================= Errors =========================
    private static func err(_ msg: String, code: Int) -> NSError {
        NSError(domain: "AIRecommender", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
