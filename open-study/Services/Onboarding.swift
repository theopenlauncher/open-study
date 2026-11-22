//
//  Onboarding.swift
//  open-study
//
//  The answers gathered during setup and how they become the user's real
//  workspace: subjects, their starting blocks, timer rhythm, goal, exams,
//  habits and preferences (DESIGN.md §13 Onboarding).
//
//  Everything here is additive. Re-running setup never deletes or renames
//  anything the user already has.
//

import Foundation
import SwiftData
import Observation
import PostHog

// MARK: - Answers

struct DraftSubject: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
    var colorKey: String
    /// Already in the sidebar (re-run): shown, but never edited or removed here.
    var existingID: UUID? = nil
    var isExisting: Bool { existingID != nil }
}

struct DraftExam: Identifiable, Hashable {
    var id = UUID()
    var title = ""
    var subjectID: UUID?
    var date: Date = Calendar.current.date(byAdding: .day, value: 14, to: Calendar.current.startOfDay(for: .now)) ?? .now
}

struct DraftHabit: Identifiable, Hashable {
    var id: String { OnboardingDraft.habitKey(name) }
    let name: String
    let symbol: String
}

/// The study tools a subject page can start with. Each maps to an empty widget block.
enum StudyTool: String, CaseIterable, Identifiable {
    case tasks, flashcards, quiz, pomodoro, statistics, pdf
    var id: String { rawValue }

    var block: BlockKind {
        switch self {
        case .tasks: .tasks
        case .flashcards: .flashcards
        case .quiz: .quiz
        case .pomodoro: .pomodoro
        case .statistics: .statistics
        case .pdf: .pdf
        }
    }

    var title: String {
        switch self {
        case .tasks: "Tasks & deadlines"
        case .flashcards: "Flashcards"
        case .quiz: "Practice quizzes"
        case .pomodoro: "Focus timer"
        case .statistics: "Progress charts"
        case .pdf: "PDFs & readings"
        }
    }

    var subtitle: String {
        switch self {
        case .tasks: "Homework and due dates per subject"
        case .flashcards: "Spaced repetition for things to memorise"
        case .quiz: "Test yourself before the real thing"
        case .pomodoro: "Start a session right from the page"
        case .statistics: "See how much each subject gets"
        case .pdf: "Read and highlight course material"
        }
    }

    var symbol: String { block.symbol }
}

/// Focus / break lengths offered during setup.
enum FocusRhythm: String, CaseIterable, Identifiable {
    case short, classic, deep
    var id: String { rawValue }

    var title: String {
        switch self {
        case .short: "Short bursts"
        case .classic: "Classic"
        case .deep: "Deep work"
        }
    }

    var detail: String {
        switch self {
        case .short: "Easier to start. Good when focus is hard to find."
        case .classic: "The standard Pomodoro. A steady default."
        case .deep: "Long stretches for problem sets and essays."
        }
    }

    var focus: Int { switch self { case .short: 15; case .classic: 25; case .deep: 50 } }
    var shortBreak: Int { switch self { case .short: 3; case .classic: 5; case .deep: 10 } }
    var longBreak: Int { switch self { case .short: 10; case .classic: 15; case .deep: 20 } }
    var longEvery: Int { switch self { case .short: 4; case .classic: 4; case .deep: 3 } }

    /// The preset matching the whole timer configuration, if any. Focus length
    /// alone isn't enough: custom breaks or cadence must survive a re-run.
    static func matching(focus: Int, shortBreak: Int, longBreak: Int, longEvery: Int) -> FocusRhythm? {
        allCases.first {
            $0.focus == focus && $0.shortBreak == shortBreak && $0.longBreak == longBreak && $0.longEvery == longEvery
        }
    }
}

@MainActor
@Observable
final class OnboardingDraft {
    var name = ""
    var subjects: [DraftSubject] = []
    var tools: Set<StudyTool> = []
    var rhythm: FocusRhythm = .classic
    /// Set when re-running with a timer configuration that matches no preset;
    /// cleared as soon as the user picks one, so their settings are kept otherwise.
    var keepCustomFocus: Int?
    /// The custom short break that goes with `keepCustomFocus`, for display.
    var customShortBreak: Int?
    var dailyGoal = 120
    var exams: [DraftExam] = []
    /// Selected habits, by normalised name (`habitKey`).
    var habits: Set<String> = []
    var customHabits: [DraftHabit] = []
    var existingHabitNames: Set<String> = []
    var appearance = "system"
    var notifications = true
    var analytics = true

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var newSubjects: [DraftSubject] { subjects.filter { !$0.isExisting } }

    /// Prefills from the current preferences and data, so a re-run starts
    /// from what the user already has.
    init(existingSubjects: [Subject] = [], existingHabits: [Habit] = []) {
        let d = UserDefaults.standard
        name = d.string(forKey: PrefKey.userName) ?? ""
        let focus = d.integer(forKey: PrefKey.focusMinutes)
        let shortBreak = d.integer(forKey: PrefKey.shortBreakMinutes)
        if let preset = FocusRhythm.matching(focus: focus, shortBreak: shortBreak,
                                             longBreak: d.integer(forKey: PrefKey.longBreakMinutes),
                                             longEvery: d.integer(forKey: PrefKey.longBreakEvery)) {
            rhythm = preset
        } else {
            keepCustomFocus = focus
            customShortBreak = shortBreak
        }
        dailyGoal = d.integer(forKey: PrefKey.dailyGoalMinutes)
        appearance = d.string(forKey: PrefKey.appearance) ?? "system"
        notifications = d.bool(forKey: PrefKey.notificationsEnabled)
        analytics = d.bool(forKey: PrefKey.analyticsEnabled)
        subjects = existingSubjects.map {
            DraftSubject(name: $0.name, symbol: $0.symbol, colorKey: $0.colorKey, existingID: $0.id)
        }
        existingHabitNames = Set(existingHabits.map { Self.habitKey($0.name) })
    }

    // MARK: Subjects

    func hasSubject(named name: String) -> Bool {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return subjects.contains { $0.name.lowercased() == key }
    }

    func addSubject(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !hasSubject(named: name) else { return }
        let used = Set(subjects.map(\.colorKey))
        let color = SubjectColor.allCases.first { !used.contains($0.rawValue) }
            ?? SubjectColor.allCases[subjects.count % SubjectColor.allCases.count]
        subjects.append(DraftSubject(name: name, symbol: SubjectGuess.symbol(for: name), colorKey: color.rawValue))
    }

    func removeSubject(_ id: UUID) {
        subjects.removeAll { $0.id == id && !$0.isExisting }
        for i in exams.indices where exams[i].subjectID == id { exams[i].subjectID = nil }
    }

    func subject(_ id: UUID?) -> DraftSubject? { subjects.first { $0.id == id } }

    // MARK: Habits

    /// Suggestions follow the tools the user picked, so they're relevant.
    var habitSuggestions: [DraftHabit] {
        var list: [DraftHabit] = []
        if tools.contains(.flashcards) { list.append(DraftHabit(name: "Review flashcards", symbol: "rectangle.on.rectangle.angled")) }
        if tools.contains(.tasks) { list.append(DraftHabit(name: "Plan tomorrow", symbol: "checklist")) }
        if tools.contains(.pdf) { list.append(DraftHabit(name: "Read for 20 minutes", symbol: "book")) }
        if tools.contains(.quiz) { list.append(DraftHabit(name: "Take a practice quiz", symbol: "questionmark.square.dashed")) }
        if tools.contains(.pomodoro) { list.append(DraftHabit(name: "Finish one focus session", symbol: "timer")) }
        list.append(DraftHabit(name: "Revise today's notes", symbol: "pencil"))
        if !tools.contains(.pdf) { list.append(DraftHabit(name: "Read for 20 minutes", symbol: "book")) }
        list.append(contentsOf: customHabits)
        // One entry per normalised name (a custom habit may match a suggestion that
        // appears later), and nothing the user already tracks.
        var seen = existingHabitNames
        return list.filter { seen.insert(Self.habitKey($0.name)).inserted }
    }

    nonisolated static func habitKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func isHabitSelected(_ habit: DraftHabit) -> Bool { habits.contains(Self.habitKey(habit.name)) }

    func toggleHabit(_ habit: DraftHabit) {
        let key = Self.habitKey(habit.name)
        if habits.contains(key) { habits.remove(key) } else { habits.insert(key) }
    }

    func addCustomHabit(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let key = Self.habitKey(name)
        if !customHabits.contains(where: { Self.habitKey($0.name) == key }) {
            customHabits.append(DraftHabit(name: name, symbol: "checkmark.circle"))
        }
        habits.insert(key)
    }

    var chosenHabits: [DraftHabit] { habitSuggestions.filter(isHabitSelected) }

    // MARK: Derived

    var focusMinutes: Int { keepCustomFocus ?? rhythm.focus }

    /// Honest arithmetic: sessions needed to reach the goal at this focus length.
    var sessionsForGoal: Int { max(1, Int((Double(dailyGoal) / Double(max(1, focusMinutes))).rounded(.up))) }

    /// Order and widths of the blocks every new subject page starts with.
    var starterBlocks: [(kind: BlockKind, width: Double)] {
        let halves = StudyTool.allCases.filter { tools.contains($0) && $0 != .pdf }
        var result: [(BlockKind, Double)] = halves.enumerated().map { i, tool in
            // An odd last block fills its row instead of leaving a gap.
            (tool.block, (i == halves.count - 1 && halves.count.isMultiple(of: 2) == false) ? 1.0 : 0.5)
        }
        if tools.contains(.pdf) { result.append((.pdf, 1.0)) }
        return result
    }
}

// MARK: - Subject icon guess

/// Picks a fitting symbol from the subject editor's set; the user can change it.
enum SubjectGuess {
    private static let table: [(keywords: [String], symbol: String)] = [
        (["math", "calc", "algebra", "geometry", "statistic", "stats", "further"], "function"),
        (["physic", "mechanic", "astro"], "atom"),
        (["chem"], "flask"),
        (["bio", "ecolog", "botan", "zoolog", "environment"], "leaf"),
        (["geog", "earth", "global"], "globe.europe.africa"),
        (["histor", "politic", "government", "civics", "classics", "philosoph", "religio"], "building.columns"),
        (["english", "literat", "language", "french", "spanish", "german", "latin", "chinese", "japanese", "writing", "linguist"], "character.book.closed"),
        (["music"], "music.note"),
        (["art", "design", "drawing", "photo"], "paintpalette"),
        (["computer", "comp sci", "cs", "programming", "coding", "software", "data", "ict", "it"], "cpu"),
        (["econ", "business", "finance", "account", "market"], "chart.line.uptrend.xyaxis"),
        (["psych", "neuro", "sociol", "cognitive"], "brain.head.profile"),
        (["medic", "health", "anatomy", "nursing", "physiol", "pharma"], "heart.text.square"),
        (["law", "legal"], "scalemass"),
        (["engineer", "technolog", "electronic", "robot"], "hammer"),
        (["drama", "theat", "film", "media"], "theatermasks"),
    ]

    static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        for row in table {
            for key in row.keywords {
                // Short keys ("cs", "it", "art") must match a whole word, longer ones a prefix.
                if key.count <= 3 ? words.contains(key) : (words.contains { $0.hasPrefix(key) } || lower.contains(key)) {
                    return row.symbol
                }
            }
        }
        return "book.closed"
    }

    static let suggestions = ["Maths", "Biology", "Chemistry", "Physics", "History", "English", "Computer science", "Economics", "Psychology"]
}

// MARK: - Applying

@MainActor
enum Onboarding {
    /// People who used Open Study before onboarding existed already have a
    /// workspace; don't put them through first-run setup.
    static func migrateExistingUser(container: ModelContainer) {
        let d = UserDefaults.standard
        guard d.object(forKey: PrefKey.onboardingCompleted) == nil else { return }
        let count = (try? container.mainContext.fetchCount(FetchDescriptor<Subject>())) ?? 0
        if count > 0 { d.set(true, forKey: PrefKey.onboardingCompleted) }
    }

    /// Writes the answers into the store and preferences. Only adds; never deletes.
    /// The store is saved first: if that fails, the inserts are rolled back, no
    /// preference changes, setup stays open and a retry can't duplicate anything.
    static func apply(_ draft: OnboardingDraft, context: ModelContext, engine: PomodoroEngine) throws {
        // Subjects, each with the empty tool blocks the user chose.
        let existing = (try? context.fetch(FetchDescriptor<Subject>())) ?? []
        var nextIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        var created: [UUID: Subject] = [:]
        for s in existing { created[s.id] = s }
        let starter = draft.starterBlocks
        for draftSubject in draft.subjects {
            if let id = draftSubject.existingID {
                if let subject = existing.first(where: { $0.id == id }) { created[draftSubject.id] = subject }
                continue
            }
            let subject = Subject(name: draftSubject.name, symbol: draftSubject.symbol,
                                  colorKey: draftSubject.colorKey, sortIndex: nextIndex)
            nextIndex += 1
            context.insert(subject)
            for (i, item) in starter.enumerated() {
                let block = Block(kind: item.kind, sortIndex: i)
                block.widthFraction = item.width
                context.insert(block)
                block.subject = subject
            }
            created[draftSubject.id] = subject
        }

        // Exams become all-day calendar events, like the Calendar's own editor makes.
        let cal = Calendar.current
        for exam in draft.exams {
            let subject = exam.subjectID.flatMap { created[$0] }
            let title = exam.title.trimmingCharacters(in: .whitespaces)
                .ifEmpty(subject.map { "\($0.name) exam" } ?? "Exam")
            let start = cal.startOfDay(for: exam.date)
            let end = cal.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-60)
            context.insert(StudyEvent(title: title, kind: .exam, start: start, end: end, isAllDay: true, subject: subject))
        }

        // Habits.
        let habitBase = ((try? context.fetch(FetchDescriptor<Habit>()))?.map(\.sortIndex).max() ?? -1) + 1
        for (i, habit) in draft.chosenHabits.enumerated() {
            context.insert(Habit(name: habit.name, symbol: habit.symbol, sortIndex: habitBase + i))
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        let d = UserDefaults.standard
        d.set(draft.trimmedName, forKey: PrefKey.userName)

        // Rhythm and goal. A custom timer from before is kept unless a preset was picked.
        if draft.keepCustomFocus == nil {
            d.set(draft.rhythm.focus, forKey: PrefKey.focusMinutes)
            d.set(draft.rhythm.shortBreak, forKey: PrefKey.shortBreakMinutes)
            d.set(draft.rhythm.longBreak, forKey: PrefKey.longBreakMinutes)
            d.set(draft.rhythm.longEvery, forKey: PrefKey.longBreakEvery)
            engine.resetDurations()
        }
        d.set(draft.dailyGoal, forKey: PrefKey.dailyGoalMinutes)

        // Look and privacy (appearance is already applied live while choosing).
        d.set(draft.appearance, forKey: PrefKey.appearance)
        d.set(draft.notifications, forKey: PrefKey.notificationsEnabled)
        if draft.notifications { NotificationDelegate.requestAuthorization() }
        d.set(draft.analytics, forKey: PrefKey.analyticsEnabled)
        Analytics.setEnabled(draft.analytics)

        // Counts and choices only — never names or titles.
        PostHogSDK.shared.capture("onboarding_completed", properties: [
            "subjects_added": draft.newSubjects.count,
            "tools": draft.tools.map(\.rawValue).sorted().joined(separator: ","),
            "focus_minutes": draft.focusMinutes,
            "daily_goal_minutes": draft.dailyGoal,
            "exams_added": draft.exams.count,
            "habits_added": draft.chosenHabits.count,
            "has_name": !draft.trimmedName.isEmpty,
        ])
        d.set(true, forKey: PrefKey.onboardingCompleted)
    }

    /// "Skip setup": nothing is written except that setup has been seen.
    static func skip() {
        PostHogSDK.shared.capture("onboarding_skipped")
        UserDefaults.standard.set(true, forKey: PrefKey.onboardingCompleted)
    }
}

// MARK: - Greeting

/// Time-of-day greeting shared by Home and onboarding's live preview of it.
enum Greeting {
    static func now(name: String = UserDefaults.standard.string(forKey: PrefKey.userName) ?? "", date: Date = .now) -> String {
        let base = switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? base : "\(base), \(trimmed)"
    }
}
