//
//  Models.swift
//  open-study
//
//  SwiftData schema. All structured data is stored locally in a single
//  SwiftData store; imported PDF files live on disk (see DocumentStore).
//
//  Delete rules are chosen to prevent accidental data loss:
//  deleting a subject removes its page blocks, but keeps tasks, decks,
//  documents, quizzes, events and focus history (they become unassigned).
//

import Foundation
import SwiftData

// MARK: - Subject

@Model
final class Subject {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "book.closed"
    var colorKey: String = SubjectColor.slate.rawValue
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Block.subject) var blocks: [Block] = []
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.subject) var tasks: [TaskItem] = []
    @Relationship(deleteRule: .nullify, inverse: \Deck.subject) var decks: [Deck] = []
    @Relationship(deleteRule: .nullify, inverse: \StudyEvent.subject) var events: [StudyEvent] = []
    @Relationship(deleteRule: .nullify, inverse: \Quiz.subject) var quizzes: [Quiz] = []
    @Relationship(deleteRule: .nullify, inverse: \StudyDocument.subject) var documents: [StudyDocument] = []
    @Relationship(deleteRule: .nullify, inverse: \FocusSession.subject) var sessions: [FocusSession] = []

    init(name: String, symbol: String = "book.closed", colorKey: String = SubjectColor.slate.rawValue, sortIndex: Int = 0) {
        self.name = name
        self.symbol = symbol
        self.colorKey = colorKey
        self.sortIndex = sortIndex
    }

    var sortedBlocks: [Block] { blocks.sorted { $0.sortIndex < $1.sortIndex } }
}

// MARK: - Blocks

enum BlockKind: String, CaseIterable, Identifiable {
    case text, heading, divider, callout, checklist, tasks, flashcards, pdf, pomodoro, statistics, quiz
    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .heading: "Heading"
        case .divider: "Divider"
        case .callout: "Callout"
        case .checklist: "Checklist"
        case .tasks: "Task list"
        case .flashcards: "Flashcards"
        case .pdf: "PDF document"
        case .pomodoro: "Pomodoro timer"
        case .statistics: "Study statistics"
        case .quiz: "Quiz"
        }
    }

    var subtitle: String {
        switch self {
        case .text: "Rich notes with formatting, lists, links and images"
        case .heading: "A section title for your page"
        case .divider: "Visually separate sections"
        case .callout: "Highlight a key idea or reminder"
        case .checklist: "A quick checklist that lives on this page"
        case .tasks: "Tasks with due dates that also appear in Tasks"
        case .flashcards: "Review a deck with spaced repetition"
        case .pdf: "Read and annotate a PDF"
        case .pomodoro: "Focus timer for this subject"
        case .statistics: "Study progress for this subject"
        case .quiz: "A practice test you can take and retake"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .heading: "textformat.size"
        case .divider: "minus"
        case .callout: "lightbulb"
        case .checklist: "checklist.checked"
        case .tasks: "checklist"
        case .flashcards: "rectangle.on.rectangle.angled"
        case .pdf: "doc.richtext"
        case .pomodoro: "timer"
        case .statistics: "chart.bar.xaxis"
        case .quiz: "questionmark.square.dashed"
        }
    }

    var keywords: String {
        switch self {
        case .text: "text note paragraph write rich"
        case .heading: "heading title h1 h2 h3 section"
        case .divider: "divider line separator rule hr"
        case .callout: "callout info note tip warning box"
        case .checklist: "checklist todo check list"
        case .tasks: "tasks todo deadline due planner"
        case .flashcards: "flashcards cards deck review anki srs"
        case .pdf: "pdf document file read annotate"
        case .pomodoro: "pomodoro timer focus clock"
        case .statistics: "statistics stats progress chart"
        case .quiz: "quiz test practice exam questions"
        }
    }

    /// Inline blocks have no card chrome (DESIGN.md §8).
    var isInline: Bool { [.text, .heading, .divider, .callout, .checklist].contains(self) }
    var supportsWidth: Bool { ![.heading, .divider].contains(self) }
    var supportsHeight: Bool { self == .pdf }
}

enum CalloutTone: String, CaseIterable, Identifiable {
    case neutral, blue, green, yellow, red
    var id: String { rawValue }
}

struct ChecklistEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var done: Bool = false
}

@Model
final class Block {
    var id: UUID = UUID()
    var kindRaw: String = BlockKind.text.rawValue
    var sortIndex: Int = 0
    var widthFraction: Double = 1.0
    var height: Double = 0
    var createdAt: Date = Date()

    // Content payloads (only the fields relevant to `kind` are used)
    var title: String = ""
    var text: String = ""
    @Attribute(.externalStorage) var richData: Data?
    var level: Int = 1
    var symbol: String = "lightbulb"
    var toneRaw: String = CalloutTone.neutral.rawValue
    var itemsData: Data?
    var showCompleted: Bool = true

    var subject: Subject?
    var deck: Deck?
    var document: StudyDocument?
    var quiz: Quiz?
    @Relationship(deleteRule: .nullify, inverse: \TaskItem.block) var tasks: [TaskItem] = []

    init(kind: BlockKind, sortIndex: Int) {
        self.kindRaw = kind.rawValue
        self.sortIndex = sortIndex
        switch kind {
        case .pdf: height = 560
        case .tasks: title = "Tasks"
        case .checklist: title = ""
        default: break
        }
    }

    var kind: BlockKind { BlockKind(rawValue: kindRaw) ?? .text }
    var tone: CalloutTone {
        get { CalloutTone(rawValue: toneRaw) ?? .neutral }
        set { toneRaw = newValue.rawValue }
    }

    var checklist: [ChecklistEntry] {
        get {
            guard let itemsData, let items = try? JSONDecoder().decode([ChecklistEntry].self, from: itemsData) else { return [] }
            return items
        }
        set { itemsData = try? JSONEncoder().encode(newValue) }
    }
}

// MARK: - Tasks

enum TaskPriority: Int, CaseIterable, Identifiable {
    case none = 0, low, medium, high
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: "No priority"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var isDone: Bool = false
    var completedAt: Date?
    var dueDate: Date?
    var priorityRaw: Int = 0
    var createdAt: Date = Date()
    var subject: Subject?
    var block: Block?

    init(title: String, subject: Subject? = nil, dueDate: Date? = nil, priority: TaskPriority = .none) {
        self.title = title
        self.subject = subject
        self.dueDate = dueDate
        self.priorityRaw = priority.rawValue
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: .now)
    }

    func toggle() {
        isDone.toggle()
        completedAt = isDone ? Date() : nil
    }
}

// MARK: - Flashcards

@Model
final class Deck {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var subject: Subject?
    @Relationship(deleteRule: .cascade, inverse: \Flashcard.deck) var cards: [Flashcard] = []
    @Relationship(deleteRule: .nullify, inverse: \Block.deck) var blocks: [Block] = []

    init(name: String, subject: Subject? = nil) {
        self.name = name
        self.subject = subject
    }

    var dueCards: [Flashcard] {
        let now = Date()
        return cards.filter { $0.dueDate <= now }.sorted { $0.dueDate < $1.dueDate }
    }
}

@Model
final class Flashcard {
    var id: UUID = UUID()
    var front: String = ""
    var back: String = ""
    var tagsRaw: String = ""
    var createdAt: Date = Date()

    // SM-2 scheduling state
    var ease: Double = 2.5
    var intervalDays: Double = 0
    var repetitions: Int = 0
    var lapses: Int = 0
    var dueDate: Date = Date()
    var lastReviewed: Date?

    var deck: Deck?
    @Relationship(deleteRule: .nullify, inverse: \ReviewLog.card) var reviews: [ReviewLog] = []

    init(front: String, back: String, tags: [String] = [], deck: Deck? = nil) {
        self.front = front
        self.back = back
        self.tagsRaw = Flashcard.encodeTags(tags)
        self.deck = deck
    }

    var tags: [String] {
        get { tagsRaw.split(separator: " ").map(String.init).filter { !$0.isEmpty } }
        set { tagsRaw = Flashcard.encodeTags(newValue) }
    }

    var isNew: Bool { repetitions == 0 && lastReviewed == nil }

    static func encodeTags(_ tags: [String]) -> String {
        tags.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_") }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

enum ReviewRating: Int, CaseIterable, Identifiable {
    case again = 0, hard, good, easy
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
    var isCorrect: Bool { self != .again }
}

@Model
final class ReviewLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var ratingRaw: Int = 0
    /// Snapshot so statistics survive card/deck deletion.
    var subjectID: UUID?
    var card: Flashcard?

    init(rating: ReviewRating, card: Flashcard) {
        self.ratingRaw = rating.rawValue
        self.card = card
        self.subjectID = card.deck?.subject?.id
    }

    var rating: ReviewRating { ReviewRating(rawValue: ratingRaw) ?? .good }
}

// MARK: - Calendar

enum EventKind: String, CaseIterable, Identifiable {
    case study, exam, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .study: "Study session"
        case .exam: "Exam"
        case .other: "Event"
        }
    }
    var symbol: String {
        switch self {
        case .study: "book"
        case .exam: "flag.fill"
        case .other: "calendar"
        }
    }
}

@Model
final class StudyEvent {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = EventKind.study.rawValue
    var start: Date = Date()
    var end: Date = Date()
    var isAllDay: Bool = false
    var notes: String = ""
    var subject: Subject?

    init(title: String, kind: EventKind, start: Date, end: Date, isAllDay: Bool = false, subject: Subject? = nil) {
        self.title = title
        self.kindRaw = kind.rawValue
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.subject = subject
    }

    var kind: EventKind {
        get { EventKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }
}

// MARK: - Focus sessions

@Model
final class FocusSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var seconds: Double = 0
    var completed: Bool = false
    var taskTitle: String = ""
    var subject: Subject?

    init(startedAt: Date, endedAt: Date, seconds: Double, completed: Bool, subject: Subject?, taskTitle: String) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.seconds = seconds
        self.completed = completed
        self.subject = subject
        self.taskTitle = taskTitle
    }
}

// MARK: - Documents

@Model
final class StudyDocument {
    var id: UUID = UUID()
    var title: String = ""
    /// File name inside the app's Documents folder (see DocumentStore).
    var fileName: String = ""
    var importedAt: Date = Date()
    var lastPage: Int = 0
    var subject: Subject?
    @Relationship(deleteRule: .nullify, inverse: \Block.document) var blocks: [Block] = []

    init(title: String, fileName: String, subject: Subject? = nil) {
        self.title = title
        self.fileName = fileName
        self.subject = subject
    }
}

// MARK: - Quizzes

enum QuestionKind: String, CaseIterable, Identifiable {
    case multipleChoice, trueFalse, shortAnswer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .trueFalse: "True / False"
        case .shortAnswer: "Short answer"
        }
    }
}

@Model
final class Quiz {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var subject: Subject?
    @Relationship(deleteRule: .cascade, inverse: \QuizQuestion.quiz) var questions: [QuizQuestion] = []
    @Relationship(deleteRule: .cascade, inverse: \QuizAttempt.quiz) var attempts: [QuizAttempt] = []
    @Relationship(deleteRule: .nullify, inverse: \Block.quiz) var blocks: [Block] = []

    init(title: String, subject: Subject? = nil) {
        self.title = title
        self.subject = subject
    }

    var sortedQuestions: [QuizQuestion] { questions.sorted { $0.sortIndex < $1.sortIndex } }
    var bestScore: Double? {
        attempts.filter { $0.total > 0 }.map { Double($0.score) / Double($0.total) }.max()
    }
}

@Model
final class QuizQuestion {
    var id: UUID = UUID()
    var prompt: String = ""
    var kindRaw: String = QuestionKind.multipleChoice.rawValue
    var options: [String] = []
    var correctIndex: Int = 0
    var correctBool: Bool = true
    var correctText: String = ""
    var sortIndex: Int = 0
    var quiz: Quiz?

    init(kind: QuestionKind, sortIndex: Int) {
        self.kindRaw = kind.rawValue
        self.sortIndex = sortIndex
        if kind == .multipleChoice { options = ["", ""] }
    }

    var kind: QuestionKind {
        get { QuestionKind(rawValue: kindRaw) ?? .multipleChoice }
        set {
            kindRaw = newValue.rawValue
            if newValue == .multipleChoice && options.count < 2 { options = ["", ""] }
        }
    }

    /// A question is answerable once it has a prompt and a valid correct answer.
    var isComplete: Bool {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch kind {
        case .multipleChoice:
            let filled = options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return filled.count >= 2 && options.indices.contains(correctIndex)
                && !options[correctIndex].trimmingCharacters(in: .whitespaces).isEmpty
        case .trueFalse: return true
        case .shortAnswer: return !correctText.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

@Model
final class QuizAttempt {
    var id: UUID = UUID()
    var date: Date = Date()
    var score: Int = 0
    var total: Int = 0
    var quiz: Quiz?

    init(score: Int, total: Int) {
        self.score = score
        self.total = total
    }
}

// MARK: - Habits

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "checkmark.circle"
    var createdAt: Date = Date()
    var sortIndex: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \HabitCheck.habit) var checks: [HabitCheck] = []

    init(name: String, symbol: String, sortIndex: Int) {
        self.name = name
        self.symbol = symbol
        self.sortIndex = sortIndex
    }

    var checkedDays: Set<Date> {
        Set(checks.map { Calendar.current.startOfDay(for: $0.day) })
    }

    func isDone(on day: Date) -> Bool {
        checkedDays.contains(Calendar.current.startOfDay(for: day))
    }
}

@Model
final class HabitCheck {
    var id: UUID = UUID()
    var day: Date = Date()
    var habit: Habit?

    init(day: Date) {
        self.day = Calendar.current.startOfDay(for: day)
    }
}

// MARK: - Schema

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Subject.self, Block.self, TaskItem.self, Deck.self, Flashcard.self, ReviewLog.self,
        StudyEvent.self, FocusSession.self, StudyDocument.self, Quiz.self, QuizQuestion.self,
        QuizAttempt.self, Habit.self, HabitCheck.self,
    ]
}
