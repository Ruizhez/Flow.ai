//
//  CurrentPlanView.swift
//  InternalFlow
//
//  Created by Ruizhe Zheng on 10/15/25.
//


//
//  CurrentPlanView.swift
//  InternalFlow
//
//  需求：
//  1) 用户先选择当下情绪
//  2) 用所选情绪调用 EventManager 算出推荐（返回文案）
//  3) 从文案中抽出事件名 → 在“数据库”（此处用 EventManager.loadEvents 本地表）里
//     找到完整 Event（难度/预计用时/截止日期等）
//  4) 把事件 + 情绪丢给 AIExplainerAgent（gpt-4o）生成“为何推荐”的解释
//

import SwiftUI

struct CurrentPlanView: View {
    // 建议用 Info.plist (OPENAI_API_KEY) 提供 Key；也可依赖注入
    private let agent: AIExplainerAgent

    @State private var selectedEmotion: Emotion = .uneasy
    @State private var message: String = ""               // EventManager 返回的提示文案
    @State private var recommendedEvent: Event?           // 从“数据库”里查到的完整事件
    @State private var explanation: String = ""           // gpt-4o 的解释
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(agent: AIExplainerAgent? = nil) {
        if let a = agent {
            self.agent = a
        } else {
            let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
            self.agent = AIExplainerAgent(apiKey: key)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Current Plan")
                .font(.largeTitle)
                .bold()

            // 1) 选择情绪
            VStack(alignment: .leading, spacing: 8) {
                Text("How do you feel right now?")
                    .font(.headline)
                Picker("", selection: $selectedEmotion) {
                    Text("Alert").tag(Emotion.alert)
                    Text("Focused").tag(Emotion.focus)
                    Text("Anxious").tag(Emotion.uneasy)
                    Text("Distracted").tag(Emotion.distracted)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            // 2) 展示 EventManager 的文案
            if !message.isEmpty {
                Text(message)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }

            // 3) 展示完整事件信息（从“数据库”查到）
            if let e = recommendedEvent {
                EventCardView(event: e)
                    .padding(.horizontal)
            }

            // 动作区
            HStack(spacing: 12) {
                Button {
                    runRecommendation()
                } label: {
                    Label("Find Recommendation", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)

                Button {
                    explainWhy()
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label("Explain Why", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(recommendedEvent == nil || isLoading)
            }

            // 4) gpt-4o 解释 / 错误
            if let err = errorMessage {
                Text(err).foregroundStyle(.red).padding(.horizontal)
            } else if !explanation.isEmpty {
                Text(explanation)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }

            Spacer(minLength: 0)
        }
        .navigationTitle("Current Plan")
    }

    // MARK: - Core flow

    private func runRecommendation() {
        // 用所选情绪跑 EventManager
        let msg = EventManager.shared.getTodaysRandomEvent(emotion: selectedEmotion.rawValue)
        message = msg
        explanation = ""
        errorMessage = nil

        // 从文案中抽出事件名
        guard let name = extractEventName(from: msg) else {
            recommendedEvent = nil
            return
        }

        // 在“数据库”里按名称查完整事件（此处用本地 events.json；
        // 如果你有远端 DB，把这一步替换成你的网络请求即可）
        recommendedEvent = findEventByName(name)
    }

    private func explainWhy() {
        guard let e = recommendedEvent else { return }
        isLoading = true
        explanation = ""
        errorMessage = nil

        Task {
            defer { isLoading = false }
            do {
                let text = try await agent.explainRecommendation(event: e, userEmotion: selectedEmotion)
                explanation = text
            } catch {
                errorMessage = "Explanation unavailable: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    /// 从提示文案中提取事件名：
    /// 例如 "You could do this today: Math Homework" / "今天可以做这个：数学作业"
    private func extractEventName(from msg: String) -> String? {
        let lowers = msg.lowercased()
        // 屏蔽空状态/错误提示
        if lowers.contains("nothing") || lowers.contains("no suitable") || lowers.contains("can't recognize") {
            return nil
        }
        // 按冒号（英文/中文）取最后一段
        if let r = msg.range(of: ":", options: .backwards) ?? msg.range(of: "：", options: .backwards) {
            let name = msg[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
        return nil
    }

    /// 在“数据库”中（此处用本地 events.json）按名称查找事件；
    /// 若同名多条，取截止更近的一条
    private func findEventByName(_ name: String) -> Event? {
        EventManager.shared.loadEvents()
            .filter { $0.name == name }
            .sorted { $0.deadline < $1.deadline }
            .first
    }
}

// 事件信息卡片
private struct EventCardView: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.name)
                .font(.title3).bold()
            HStack {
                Label(dateString(event.deadline), systemImage: "calendar")
                Spacer()
                Label("\(String(format: "%.1f", event.estimatetimes)) h", systemImage: "clock")
                Spacer()
                Label(event.level, systemImage: "flag")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func dateString(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: d)
    }
}
