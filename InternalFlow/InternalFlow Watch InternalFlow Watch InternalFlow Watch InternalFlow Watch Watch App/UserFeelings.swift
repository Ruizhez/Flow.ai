import SwiftUI

struct UserFeelings: View {
    @State private var message: String = "How do you feel right now?"
    @State private var reason: String?
    @State private var isLoading = false
    @State private var lastError: String?

    // 开关：是否使用 AI（关掉则只用本地规则）
    @AppStorage("useAIRecommend") private var useAIRecommend = true

    // 你的 OpenAI Key（开发期可用 .xcconfig 或 Scheme 的环境变量注入）
    private var openAIKey: String? {
        // 1) 先从环境变量读（Product > Scheme > Edit Scheme > Run > Environment）
        if let k = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !k.isEmpty { return k }
        // 2) 或者临时硬编码一个占位（发布前请移除）
        // return "<PUT_YOUR_KEY_HERE>"
        return nil
    }

    // 你界面上要展示的情绪按钮（纯字符串，不依赖项目里的 Emotion 枚举）
    private let feelings: [String] = [
        "Alert", "Focused", "Uneasy", "Distracted",
        "Calm", "Tired", "Anxious", "Motivated"
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            if let r = reason, !r.isEmpty {
                Text(r)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let e = lastError {
                Text(e)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if isLoading {
                ProgressView().padding(.bottom, 4)
            }

            // 设置开关
            Toggle("Use AI Recommender", isOn: $useAIRecommend)
                .font(.footnote)
                .tint(.blue)
                .padding(.horizontal)

            // 按钮网格
            let cols = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(feelings, id: \.self) { f in
                    Button {
                        onPickFeeling(f)
                    } label: {
                        Text(f)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Start Now")
    }

    // MARK: - Actions

    private func onPickFeeling(_ feeling: String) {
        lastError = nil
        isLoading = true
        reason = nil
        message = "Thinking…"

        // —— 取出待选任务（两种写法，任选一种能编译的）——
        let events: [Event] = EventManager.shared._if_events_snapshot()

        Task {
            defer { isLoading = false }

            guard !events.isEmpty else {
                message = "No pending events."
                return
            }

            // 走 AI 或本地规则
            if useAIRecommend, let key = openAIKey, !key.isEmpty {
                do {
                    let ctx = AIContext(emotion: feeling) // 你也可以把最新 HR/HRV 填进来
                    let rec = try await AIRecommender.recommend(events: events, ctx: ctx, apiKey: key)
                    if let picked = events.first(where: { $0.id == rec.chosenEventId }) {
                        message = summaryLine(for: picked)
                        reason  = "AI: \(rec.reason)"
                    } else {
                        // 模型返回的 ID 不在列表里，回退本地
                        let picked = pickByLocalRule(from: events, feeling: feeling)
                        message = summaryLine(for: picked)
                        reason  = "AI fallback: ID not found. Used local rule."
                    }
                } catch {
                    let picked = pickByLocalRule(from: events, feeling: feeling)
                    message = summaryLine(for: picked)
                    reason  = "Local rule (AI error)."
                    lastError = error.localizedDescription
                }
            } else {
                let picked = pickByLocalRule(from: events, feeling: feeling)
                message = summaryLine(for: picked)
                reason  = "Local rule."
                if useAIRecommend, openAIKey == nil {
                    lastError = "Missing OPENAI_API_KEY."
                }
            }
        }
    }

    // MARK: - Local fallback rule (contained in this file)

    private func pickByLocalRule(from events: [Event], feeling: String) -> Event {
        let now = Date()
        // 打分：紧迫度 + 估时快一点 + 难度匹配 + 到期加成
        let scored: [(Event, Double)] = events.map { e in
            let urgency = urgencyScore(deadline: _deadline(of: e) ?? now, now: now)
            let quick   = quickWinsScore(hours: _hours(of: e) ?? 1.0)
            let diff    = difficultyFitScore(raw: _difficultyRaw(of: e), feeling: feeling)
            let boost   = specialDateBoost(deadline: _deadline(of: e), now: now)
            let s = 0.6 * urgency + 0.25 * diff + 0.15 * quick + boost
            return (e, s)
        }
        .sorted { $0.1 > $1.1 }

        return scored.first?.0 ?? events.first!
    }

    private func urgencyScore(deadline: Date, now: Date) -> Double {
        let dt = deadline.timeIntervalSince(now) / 86_400.0
        if dt <= 0 { return 1.0 }
        let horizon = 14.0
        let clamped = max(0, min(1, 1 - dt / horizon))
        return pow(clamped, 0.7)
    }

    private func quickWinsScore(hours: Double) -> Double {
        if hours <= 0.5 { return 1.0 }
        if hours <= 1.0 { return 0.6 }
        return 0.2
    }

    private func difficultyFitScore(raw: String?, feeling: String) -> Double {
        // 把 feeling 字符串粗分成 三档：stressed / neutral / energized
        let bucket: Int = {
            let l = feeling.lowercased()
            if ["anxious","uneasy","tired","distracted","stressed","overwhelmed"].contains(where: { l.contains($0) }) { return 0 }
            if ["alert","focused","motivated","energetic","energized","happy"].contains(where: { l.contains($0) }) { return 2 }
            return 1
        }()
        let d = (raw ?? "").lowercased()
        let isEasy = d.contains("easy") || d.contains("low") || d.contains("simple")
        let isHard = d.contains("hard") || d.contains("high") || d.contains("difficult")
        // 0=stressed, 1=neutral, 2=energized
        switch bucket {
        case 0: return isEasy ? 1.0 : (isHard ? 0.25 : 0.6)
        case 2: return isHard ? 1.0 : (isEasy ? 0.25 : 0.6)
        default: return isEasy ? 0.6 : (isHard ? 0.6 : 1.0)
        }
    }

    private func specialDateBoost(deadline: Date?, now: Date) -> Double {
        guard let d = deadline else { return 0 }
        let cal = Calendar.current
        if cal.isDate(d, inSameDayAs: now) { return 0.2 }
        if d < now { return 0.3 }
        return 0
    }

    private func summaryLine(for e: Event) -> String {
        let name = _name(of: e) ?? "Untitled"
        let hrs  = String(format: "%.2f", _hours(of: e) ?? 1.0)
        let due  = (_deadline(of: e) ?? Date()).formatted(date: .abbreviated, time: .shortened)
        let diff = (_difficultyRaw(of: e) ?? "").capitalized
        return "Try: \(name)\n(\(diff.isEmpty ? "Medium" : diff), \(hrs)h, due \(due))"
    }

    // MARK: - Event field extractors（兼容不同主文件字段命名）

    private func _id(of e: Event) -> UUID? {
        let m = Mirror(reflecting: e)
        for c in m.children where c.label == "id" {
            if let u = c.value as? UUID { return u }
            if let s = c.value as? String, let u = UUID(uuidString: s) { return u }
        }
        return nil
    }

    private func _name(of e: Event) -> String? {
        let m = Mirror(reflecting: e)
        for c in m.children {
            if c.label == "name", let s = c.value as? String { return s }
            if c.label == "title", let s = c.value as? String { return s }
        }
        return nil
    }

    private func _deadline(of e: Event) -> Date? {
        let m = Mirror(reflecting: e)
        for c in m.children {
            if c.label == "deadline", let d = c.value as? Date { return d }
            if c.label == "dueDate",  let d = c.value as? Date { return d }
            if c.label == "date",     let d = c.value as? Date { return d }
        }
        return nil
    }

    private func _hours(of e: Event) -> Double? {
        let m = Mirror(reflecting: e)
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

    private func _difficultyRaw(of e: Event) -> String? {
        let m = Mirror(reflecting: e)
        for c in m.children {
            if ["difficulty","level"].contains(c.label ?? "") {
                if let s = c.value as? String { return s }
                if let r = c.value as? CustomStringConvertible { return r.description }
                return "\(c.value)"
            }
        }
        return nil
    }

    // MARK: - Event list access（两种写法，挑一个让它编译）
    
}
// 从 EventManager.shared 中“反射”出 [Event]。不改 EventManager 的前提下获取候选。
fileprivate extension EventManager {
    func _if_events_snapshot() -> [Event] {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if let arr = child.value as? [Event] {
                return arr
            }
        }
        return []
    }
}
