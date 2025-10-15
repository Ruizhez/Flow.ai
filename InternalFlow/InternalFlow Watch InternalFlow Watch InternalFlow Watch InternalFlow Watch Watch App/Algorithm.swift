//
//  Algorithm.swift
//  InternalFlow Watch InternalFlow Watch InternalFlow Watch InternalFlow Watch Watch App
//
//  Created by Ruizhe Zheng on 4/25/25.
//
import Foundation

// MARK: - Expected Event model (adjust if your names differ)
/*
 struct Event: Identifiable, Codable, Equatable {
     let id: UUID
     var name: String
     var deadline: Date
     var estimatedHours: Double      // e.g. 0.5, 1, 2
     var difficulty: Difficulty      // .easy / .medium / .hard
     var isDone: Bool
 }

 enum Difficulty: String, Codable, CaseIterable {
     case easy, medium, hard
 }
*/

// MARK: - Context passed in when recommending a task
public struct RecommendationContext {
    public var emotion: Emotion
    public var heartRateBPM: Double?      // optional: latest HR
    public var hrvSDNNms: Double?         // optional: latest HRV (SDNN in ms)
    public var now: Date

    public init(
        emotion: Emotion,
        heartRateBPM: Double? = nil,
        hrvSDNNms: Double? = nil,
        now: Date = Date()
    ) {
        self.emotion = emotion
        self.heartRateBPM = heartRateBPM
        self.hrvSDNNms = hrvSDNNms
        self.now = now
    }
}

// MARK: - Supported emotions (map your UI buttons to these)
public enum Emotion: String, CaseIterable {
    case calm, motivated, anxious, tired, happy, overwhelmed
}

// MARK: - Tunable Weights
public struct AlgoWeights {
    public var urgency: Double = 0.45          // deadlines
    public var durationFit: Double = 0.20      // short/long match to state
    public var difficultyFit: Double = 0.20
    public var quickWins: Double = 0.10        // bias toward small tasks
    public var variety: Double = 0.05          // avoid repeating same task

    // Penalties / boosts
    public var overduePenalty: Double = -0.30  // if deadline passed
    public var dueTodayBoost: Double = 0.20    // if deadline is today

    public init() {}
}

// MARK: - Memory for variety (very light; you can swap to persistent store)
public final class AlgoMemory {
    public static let shared = AlgoMemory()
    private init() {}

    // Track last-picked event IDs to slightly downweight repetition.
    private var recentlyPicked: [UUID] = []

    public func markPicked(_ id: UUID) {
        recentlyPicked.append(id)
        if recentlyPicked.count > 10 { recentlyPicked.removeFirst() }
    }

    public func repetitionPenalty(for id: UUID) -> Double {
        // If we saw it very recently, apply a small penalty.
        guard let idx = recentlyPicked.lastIndex(of: id) else { return 0 }
        let distanceFromEnd = recentlyPicked.count - 1 - idx
        // More recent → stronger penalty; fades quickly.
        switch distanceFromEnd {
        case 0: return -0.10
        case 1: return -0.06
        case 2: return -0.03
        default: return 0
        }
    }
}

// MARK: - Core Recommender
public enum Recommender {

    /// Pick the best event for "Start Now".
    /// - Parameters:
    ///   - events: candidate events
    ///   - ctx: current user state (emotion + optional HR/HRV)
    ///   - weights: tunable weights
    /// - Returns: best event and a debug score breakdown
    public static func recommend(
        from events: [Event],
        ctx: RecommendationContext,
        weights: AlgoWeights = .init()
    ) -> (event: Event, breakdown: ScoreBreakdown)? {

        let candidates = events.filter { !$0.isDone }
        guard !candidates.isEmpty else { return nil }

        var best: (Event, ScoreBreakdown)? = nil
        for e in candidates {
            let bd = score(event: e, ctx: ctx, weights: weights)
            if let cur = best {
                if bd.total > cur.1.total { best = (e, bd) }
            } else {
                best = (e, bd)
            }
        }
        if let chosen = best { AlgoMemory.shared.markPicked(chosen.0.id) }
        return best
    }

    // MARK: Score Components

    public struct ScoreBreakdown {
        public let urgency: Double
        public let durationFit: Double
        public let difficultyFit: Double
        public let quickWins: Double
        public let variety: Double
        public let dueTodayBoost: Double
        public let overduePenalty: Double
        public let total: Double
    }

    private static func score(event e: Event, ctx: RecommendationContext, weights w: AlgoWeights) -> ScoreBreakdown {
        // 1) Urgency: normalize days until deadline → [0, 1], closer = higher.
        let urgencyComp = urgencyScore(deadline: e.deadline, now: ctx.now)

        // 2) Duration fit: map emotion/physiology → preferred duration
        let durationComp = durationFitScore(estimatedHours: e.estimatedHours, ctx: ctx)

        // 3) Difficulty fit: match emotion → difficulty preference
        let difficultyComp = difficultyFitScore(difficulty: e.difficulty, ctx: ctx)

        // 4) Quick wins bias: small tasks get a little nudge
        let quickWinsComp = quickWinsScore(estimatedHours: e.estimatedHours)

        // 5) Variety penalty: avoid picking the same event repeatedly
        let varietyComp = AlgoMemory.shared.repetitionPenalty(for: e.id)

        // 6) Special date modifiers
        let (dueToday, overdue) = dateFlags(deadline: e.deadline, now: ctx.now)
        let dueTodayBoost = dueToday ? w.dueTodayBoost : 0
        let overduePen    = overdue   ? w.overduePenalty : 0

        // Weighted sum
        let total =
            w.urgency     * urgencyComp +
            w.durationFit * durationComp +
            w.difficultyFit * difficultyComp +
            w.quickWins   * quickWinsComp +
            w.variety     * varietyComp +
            dueTodayBoost + overduePen

        return ScoreBreakdown(
            urgency: urgencyComp,
            durationFit: durationComp,
            difficultyFit: difficultyComp,
            quickWins: quickWinsComp,
            variety: varietyComp,
            dueTodayBoost: dueTodayBoost,
            overduePenalty: overduePen,
            total: total
        )
    }

    // MARK: - Component Implementations

    /// Map deadline proximity to [0, 1]. Past due gets 0.
    private static func urgencyScore(deadline: Date, now: Date) -> Double {
        let seconds = deadline.timeIntervalSince(now)
        let days = seconds / 86_400.0
        if days <= 0 { return 0 } // overdue handled separately

        // 0–1 over a 0–14 day horizon. < 1 day ~ near 1.0, > 14 days ~ ~0.0
        let horizonDays: Double = 14
        let clamped = max(0, min(1, 1 - (days / horizonDays)))
        // Slight easing so really-soon deadlines stand out
        return pow(clamped, 0.7)
    }

    /// Favor shorter tasks when anxious/tired/high-HR/low-HRV; otherwise allow longer tasks.
    private static func durationFitScore(estimatedHours: Double, ctx: RecommendationContext) -> Double {
        let basePrefHours: Double = preferredDurationHours(for: ctx.emotion)
        let physShift = physiologyShift(heartRate: ctx.heartRateBPM, hrv: ctx.hrvSDNNms)
        let target = max(0.25, basePrefHours + physShift)   // never go below 15 min

        // Score = 1 when estimated close to target; decays as it diverges
        // Use a smooth decay (Cauchy-like):
        let diff = abs(estimatedHours - target)
        let scale = 1.0 + diff * diff
        return 1.0 / scale  // in (0,1]
    }

    /// Map difficulty preferences by emotion; add mild physiology nudge.
    private static func difficultyFitScore(difficulty: Difficulty, ctx: RecommendationContext) -> Double {
        let pref = preferredDifficulty(for: ctx.emotion) // easy/medium/hard
        let base: Double
        switch (pref, difficulty) {
        case (.easy, .easy), (.medium, .medium), (.hard, .hard):
            base = 1.0
        case (.easy, .medium), (.medium, .easy), (.medium, .hard), (.hard, .medium):
            base = 0.6
        case (.easy, .hard), (.hard, .easy):
            base = 0.25
        }

        // Physiology: high HR + low HRV → tilt to easier
        let phys = physiologyDifficultyTilt(heartRate: ctx.heartRateBPM, hrv: ctx.hrvSDNNms)
        return max(0, min(1, base + phys))
    }

    /// Small bias for quick wins: <= 1h gets +, <= 0.5h gets ++
    private static func quickWinsScore(estimatedHours: Double) -> Double {
        if estimatedHours <= 0.5 { return 1.0 }
        if estimatedHours <= 1.0 { return 0.6 }
        return 0.2
    }

    private static func dateFlags(deadline: Date, now: Date) -> (dueToday: Bool, overdue: Bool) {
        let cal = Calendar.current
        let isOverdue = deadline < now
        let dueToday  = cal.isDate(deadline, inSameDayAs: now)
        return (dueToday, isOverdue)
    }

    // MARK: - Preference Mappings

    private static func preferredDurationHours(for emotion: Emotion) -> Double {
        switch emotion {
        case .anxious, .tired, .overwhelmed:
            return 0.5   // prefer quick tasks
        case .calm:
            return 1.5
        case .happy, .motivated:
            return 2.0
        }
    }

    private static func preferredDifficulty(for emotion: Emotion) -> Difficulty {
        switch emotion {
        case .anxious, .tired, .overwhelmed:
            return .easy
        case .calm:
            return .medium
        case .happy, .motivated:
            return .hard
        }
    }

    /// Negative → push duration shorter; Positive → allow longer.
    private static func physiologyShift(heartRate: Double?, hrv: Double?) -> Double {
        var shift: Double = 0
        if let hr = heartRate {
            // Rough normalization: assume 55–95 bpm as common band
            if hr >= 90 { shift -= 0.5 }
            else if hr >= 80 { shift -= 0.25 }
            else if hr <= 60 { shift += 0.15 }
        }
        if let hrv = hrv {
            // Very rough: < 25ms low; 25–60ms medium; > 60ms high (watch-specific)
            if hrv < 25 { shift -= 0.35 }
            else if hrv > 60 { shift += 0.20 }
        }
        // Clamp the overall shift so it doesn't dominate
        return max(-0.75, min(0.75, shift))
    }

    /// Lucas: Small additive tilt in difficulty score based on physiology.
    private static func physiologyDifficultyTilt(heartRate: Double?, hrv: Double?) -> Double {
        var tilt: Double = 0
        if let hr = heartRate {
            if hr >= 90 { tilt -= 0.20 }
            else if  nlt -= 0.10 }
            else if hr <= 60 { tilt += 0.05 }
        }
        if let h = hrv {
            if h < 25 { tilt -= 0.15 }
            else if h > 60 { tilt += 0.10 }
        }
        return max(-0.25, min(0.25, tilt))
    }
}
