//
//  StudyLogic.swift
//  open-study
//
//  Pure scheduling / aggregation logic: SM-2 spaced repetition and streaks.
//

import Foundation

// MARK: - SM-2

enum SM2 {
    struct Outcome {
        var ease: Double
        var intervalDays: Double
        var repetitions: Int
        var lapses: Int
        var dueDate: Date
    }

    /// Maps our four-button rating onto SM-2's 0–5 quality scale.
    static func quality(for rating: ReviewRating) -> Int {
        switch rating {
        case .again: 2
        case .hard: 3
        case .good: 4
        case .easy: 5
        }
    }

    static func schedule(ease: Double, intervalDays: Double, repetitions: Int, lapses: Int,
                         rating: ReviewRating, now: Date = .now) -> Outcome {
        let q = Double(quality(for: rating))
        var newEase = ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        newEase = max(1.3, newEase)

        if rating == .again {
            // Failed recall: restart the learning steps; show again in 10 minutes.
            return Outcome(ease: newEase, intervalDays: 0, repetitions: 0, lapses: lapses + 1,
                           dueDate: now.addingTimeInterval(10 * 60))
        }

        let reps = repetitions + 1
        var interval: Double
        switch reps {
        case 1: interval = rating == .easy ? 4 : 1
        case 2: interval = rating == .hard ? 3 : 6
        default: interval = max(1, intervalDays) * newEase
        }
        if rating == .hard { interval = max(1, interval * 0.8) }
        if rating == .easy && reps > 1 { interval *= 1.3 }
        interval = interval.rounded()

        let due = Calendar.current.date(byAdding: .day, value: Int(interval), to: Calendar.current.startOfDay(for: now))
            ?? now.addingTimeInterval(interval * 86400)
        return Outcome(ease: newEase, intervalDays: interval, repetitions: reps, lapses: lapses, dueDate: due)
    }

    static func preview(for card: Flashcard, rating: ReviewRating) -> String {
        let o = schedule(ease: card.ease, intervalDays: card.intervalDays, repetitions: card.repetitions,
                         lapses: card.lapses, rating: rating)
        return rating == .again ? "10m" : Fmt.interval(days: o.intervalDays)
    }

    static func apply(_ rating: ReviewRating, to card: Flashcard, now: Date = .now) {
        let o = schedule(ease: card.ease, intervalDays: card.intervalDays, repetitions: card.repetitions,
                         lapses: card.lapses, rating: rating, now: now)
        card.ease = o.ease
        card.intervalDays = o.intervalDays
        card.repetitions = o.repetitions
        card.lapses = o.lapses
        card.dueDate = o.dueDate
        card.lastReviewed = now
    }
}

// MARK: - Streaks

enum Streaks {
    /// Current streak counts back from today (or yesterday if today has no activity yet).
    static func current(days: Set<Date>, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: .now)
        var cursor = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        var count = 0
        while days.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    static func longest(days: Set<Date>, calendar: Calendar = .current) -> Int {
        let sorted = days.sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in sorted {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }
}

extension Calendar {
    func days(back count: Int, from date: Date = .now) -> [Date] {
        let today = startOfDay(for: date)
        return (0..<count).reversed().compactMap { self.date(byAdding: .day, value: -$0, to: today) }
    }
}

// MARK: - Activity aggregation

/// Computes statistics from real stored activity. Never fabricates data.
struct ActivitySummary {
    let sessions: [FocusSession]
    let reviews: [ReviewLog]
    let tasks: [TaskItem]
    var subjectID: UUID? = nil

    private var cal: Calendar { .current }

    var filteredSessions: [FocusSession] {
        guard let subjectID else { return sessions }
        return sessions.filter { $0.subject?.id == subjectID }
    }
    var filteredReviews: [ReviewLog] {
        guard let subjectID else { return reviews }
        return reviews.filter { $0.subjectID == subjectID }
    }
    var filteredTasks: [TaskItem] {
        guard let subjectID else { return tasks }
        return tasks.filter { $0.subject?.id == subjectID }
    }

    var totalFocusSeconds: Double { filteredSessions.reduce(0) { $0 + $1.seconds } }
    var completedPomodoros: Int { filteredSessions.filter(\.completed).count }
    var reviewCount: Int { filteredReviews.count }
    var accuracy: Double? {
        let r = filteredReviews
        guard !r.isEmpty else { return nil }
        return Double(r.filter { $0.rating.isCorrect }.count) / Double(r.count)
    }
    var tasksCompleted: Int { filteredTasks.filter(\.isDone).count }

    func focusSeconds(on day: Date) -> Double {
        filteredSessions.filter { cal.isDate($0.startedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.seconds }
    }
    func reviews(on day: Date) -> Int {
        filteredReviews.filter { cal.isDate($0.date, inSameDayAs: day) }.count
    }
    func tasksCompleted(on day: Date) -> Int {
        filteredTasks.filter { $0.completedAt.map { cal.isDate($0, inSameDayAs: day) } ?? false }.count
    }

    /// Days that count toward the study streak: focus time or flashcard reviews.
    var studyDays: Set<Date> {
        var set = Set<Date>()
        for s in filteredSessions where s.seconds >= 60 { set.insert(cal.startOfDay(for: s.startedAt)) }
        for r in filteredReviews { set.insert(cal.startOfDay(for: r.date)) }
        return set
    }

    /// All activity (focus, reviews, completed tasks) per day, for the heatmap.
    var activityByDay: [Date: Double] {
        var map: [Date: Double] = [:]
        for s in filteredSessions { map[cal.startOfDay(for: s.startedAt), default: 0] += s.seconds / 60 }
        for r in filteredReviews { map[cal.startOfDay(for: r.date), default: 0] += 0.5 }
        for t in filteredTasks { if let c = t.completedAt { map[cal.startOfDay(for: c), default: 0] += 5 } }
        return map
    }

    var hasAnyData: Bool { !filteredSessions.isEmpty || !filteredReviews.isEmpty || tasksCompleted > 0 }
}
