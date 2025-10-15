//
//  EventManager.swift
//  InternalFlow
//
//  Created by Ruizhe Zheng on 4/25/25.
//


import Foundation

enum Emotion: String {
    case alert      = "Alert"
    case focus      = "Focused"
    case uneasy     = "Anxious"
    case distracted = "Distracted"
}

enum Difficulty: String {
    case easy   = "Easy"
    case medium = "Medium"
    case hard   = "Hard"
}

private let emotionDifficultyWeights: [Emotion: [String: Double]] = [
    .alert:      ["Hard": 1.0, "Medium": 0.8, "Easy": 0.6],
    .focus:      ["Medium": 1.0, "Hard": 0.7, "Easy": 0.5],
    .uneasy:     ["Easy": 1.0, "Medium": 0.6, "Hard": 0.3],
    .distracted: ["Easy": 0.8, "Medium": 0.5, "Hard": 0.2],
]

class EventManager {
    static let shared = EventManager()
    private let fileName = "events.json"

    private var fileURL: URL {
        let manager = FileManager.default
        let url = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return url.appendingPathComponent(fileName)
    }

    func loadEvents() -> [Event] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Event].self, from: data)) ?? []
    }

    func saveEvents(_ events: [Event]) {
        if let data = try? JSONEncoder().encode(events) {
            try? data.write(to: fileURL)
        }
    }

    func addEvent(name: String, deadline: Date, time: Double, level: String) {
        var events = loadEvents()
        events.append(Event(name: name, deadline: deadline, estimatetimes: time, level: level))
        saveEvents(events)
    }

    func getTodaysRandomEvent(emotion: String) -> String {
        let events = loadEvents()
        let today = Calendar.current.startOfDay(for: Date())
        let validEvents = events.filter { $0.deadline >= today }

        guard !validEvents.isEmpty else {
            return "Nothing on your plate today. Take a break!"
        }

        guard let feeling = Emotion(rawValue: emotion) else {
            return "Can't recognize your current emotion, so I can't recommend a task."
        }

        if let bestEventName = pickBestEvent(for: feeling, from: validEvents) {
            return "You could do this today: \(bestEventName)"
        } else {
            return "No suitable tasks for today. Relax a bit!"
        }
    }
    
    private func pickBestEvent(for emotion: Emotion, from events: [Event]) -> String? {
        let now = Date()
        let sortedByDate = events.sorted { $0.deadline < $1.deadline }
        let weights = emotionDifficultyWeights[emotion] ?? [:]

        let scoredEvents = sortedByDate.map { event -> (event: Event, score: Double) in
            let days = max(1.0, Calendar.current
                .dateComponents([.day], from: now, to: event.deadline)
                .day
                .map(Double.init) ?? 1.0)
            let baseScore = 1.0 / days
            let diffWeight = weights[event.level] ?? 0.5
            let finalScore = baseScore * diffWeight
            return (event, finalScore)
        }

        let best = scoredEvents.sorted {
            if $0.score == $1.score {
                return $0.event.deadline < $1.event.deadline
            }
            return $0.score > $1.score
        }.first

        return best?.event.name
    }
}
