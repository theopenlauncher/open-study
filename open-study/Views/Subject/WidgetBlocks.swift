//
//  WidgetBlocks.swift
//  open-study
//
//  Card-style study tool blocks (DESIGN.md §8 "Widget blocks").
//

import SwiftUI
import SwiftData
import Charts

struct WidgetCard<Trailing: View, Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                Text(title).font(Typo.headline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer(minLength: Space.sm)
                trailing()
            }
            .padding(.horizontal, Space.lg)
            .frame(height: 40)
            content()
        }
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
    }
}

extension WidgetCard where Trailing == EmptyView {
    init(symbol: String, title: String, @ViewBuilder content: @escaping () -> Content) {
        self.symbol = symbol
        self.title = title
        self.trailing = { EmptyView() }
        self.content = content
    }
}

/// Setup prompt shown by widget blocks that need a deck/quiz/document first.
struct BlockSetup<Actions: View>: View {
    let message: String
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(message).font(Typo.body).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.sm) { actions() }
        }
        .padding(.horizontal, Space.lg)
        .padding(.bottom, Space.lg)
    }
}

// MARK: - Task list

struct TaskListBlockView: View {
    @Bindable var block: Block
    @Environment(\.modelContext) private var context

    private var tasks: [TaskItem] {
        block.tasks.filter { block.showCompleted || !$0.isDone }.sorted(by: TaskOrdering.comparator(.due))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.sm) {
                Image(systemName: "checklist").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                TextField("Tasks", text: $block.title).textFieldStyle(.plain).font(Typo.headline)
                Spacer()
                let open = block.tasks.filter { !$0.isDone }.count
                if !block.tasks.isEmpty {
                    Text("\(open) open").font(Typo.callout.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                }
                IconButton(symbol: block.showCompleted ? "eye" : "eye.slash",
                           help: block.showCompleted ? "Hide completed" : "Show completed", size: 24) {
                    block.showCompleted.toggle()
                }
            }
            .padding(.horizontal, Space.lg)
            .frame(height: 40)

            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { i, task in
                    if i > 0 { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 30) }
                    TaskRow(task: task, showSubject: false)
                }
            }
            .padding(.horizontal, Space.lg)

            NewTaskBar(subjects: [], lockedSubject: block.subject) { task in
                context.insert(task)
                task.block = block
                try? context.save()
            }
            .padding(Space.md)
        }
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
    }
}

// MARK: - Flashcards

struct FlashcardsBlockView: View {
    @Bindable var block: Block
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @State private var review: ReviewSession?
    @State private var addCard = false
    @State private var importing = false

    var body: some View {
        if let deck = block.deck {
            WidgetCard(symbol: "rectangle.on.rectangle.angled", title: deck.name) {
                Menu {
                    Button("Open in Flashcards") { router.openDeck(deck.id) }
                    Button("Import Cards…") { importing = true }
                    Divider()
                    Menu("Show a Different Deck") { deckChoices }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.button).buttonStyle(OSButtonStyle(variant: .ghost, compact: true)).menuIndicator(.hidden).fixedSize()
            } content: {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack(spacing: Space.xl) {
                        metric("\(deck.cards.count)", "cards")
                        metric("\(deck.dueCards.count)", "due", highlight: !deck.dueCards.isEmpty)
                        metric(accuracy(deck).map { "\(Int(($0 * 100).rounded()))%" } ?? "—", "accuracy")
                    }
                    HStack(spacing: Space.sm) {
                        Button {
                            review = ReviewSession(title: deck.name, cards: deck.dueCards)
                        } label: { Label(deck.dueCards.isEmpty ? "Nothing due" : "Review \(deck.dueCards.count)", systemImage: "play.fill") }
                            .buttonStyle(OSButtonStyle(variant: .primary, compact: true))
                            .disabled(deck.dueCards.isEmpty)
                        Button { addCard = true } label: { Label("Add card", systemImage: "plus") }
                            .buttonStyle(OSButtonStyle(variant: .secondary, compact: true))
                    }
                }
                .padding(.horizontal, Space.lg)
                .padding(.bottom, Space.lg)
            }
            .sheet(item: $review) { ReviewView(session: $0) }
            .sheet(isPresented: $addCard) { CardEditor(deck: deck, card: nil) }
            .sheet(isPresented: $importing) { ImportCardsView(preselectedDeck: deck) }
        } else {
            WidgetCard(symbol: "rectangle.on.rectangle.angled", title: "Flashcards") {
                BlockSetup(message: "Show a deck here to review it with spaced repetition.") {
                    Button {
                        let deck = Deck(name: "\(block.subject?.name ?? "New") cards")
                        context.insert(deck)
                        deck.subject = block.subject
                        block.deck = deck
                        addCard = true
                    } label: { Label("Create deck", systemImage: "plus") }
                        .buttonStyle(OSButtonStyle(variant: .primary, compact: true))
                    if !decks.isEmpty {
                        Menu("Use existing deck") { deckChoices }
                            .menuStyle(.button).buttonStyle(OSButtonStyle(variant: .secondary, compact: true)).fixedSize()
                    }
                }
            }
        }
    }

    @ViewBuilder private var deckChoices: some View {
        let mine = decks.filter { $0.subject?.id == block.subject?.id && block.subject != nil }
        let others = decks.filter { !mine.contains($0) }
        ForEach(mine) { d in Button(d.name) { block.deck = d } }
        if !mine.isEmpty && !others.isEmpty { Divider() }
        ForEach(others) { d in Button(d.name) { block.deck = d } }
    }

    private func accuracy(_ deck: Deck) -> Double? {
        let logs = deck.cards.flatMap(\.reviews)
        guard !logs.isEmpty else { return nil }
        return Double(logs.filter { $0.rating.isCorrect }.count) / Double(logs.count)
    }

    private func metric(_ value: String, _ unit: String, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(Typo.numeralSmall).foregroundStyle(highlight ? Theme.warning : Theme.textPrimary)
            Text(unit).font(Typo.callout).foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - PDF

struct PDFBlockView: View {
    @Bindable var block: Block
    @Environment(\.modelContext) private var context
    @Query(sort: \StudyDocument.importedAt, order: .reverse) private var documents: [StudyDocument]
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        if let doc = block.document {
            PDFReader(document: doc, compact: true) { block.document = nil }
                .frame(height: max(240, block.height))
                .background(Theme.raised)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
        } else {
            WidgetCard(symbol: "doc.richtext", title: "PDF document") {
                BlockSetup(message: "Add a PDF to read and annotate it right on this page. A copy is stored inside Open Study.") {
                    Button {
                        importPDF()
                    } label: {
                        if importing {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Importing…") }
                        } else {
                            Label("Import PDF…", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(OSButtonStyle(variant: .primary, compact: true))
                    .disabled(importing)
                    if !documents.isEmpty {
                        Menu("Use imported PDF") {
                            ForEach(documents) { d in Button(d.title) { block.document = d } }
                        }
                        .menuStyle(.button).buttonStyle(OSButtonStyle(variant: .secondary, compact: true)).fixedSize()
                    }
                }
                if let error { InlineErrorView(message: error).padding([.horizontal, .bottom], Space.lg) }
            }
        }
    }

    private func importPDF() {
        guard let url = DocumentStore.shared.choosePDF() else { return }
        importing = true
        error = nil
        DispatchQueue.main.async {
            defer { importing = false }
            do {
                let result = try DocumentStore.shared.importPDF(from: url)
                let doc = StudyDocument(title: result.title, fileName: result.fileName)
                context.insert(doc)
                doc.subject = block.subject
                block.document = doc
                try? context.save()
            } catch let e {
                error = e.localizedDescription
            }
        }
    }
}

// MARK: - Pomodoro

struct PomodoroBlockView: View {
    let block: Block
    @Query private var sessions: [FocusSession]

    private var todaySeconds: Double {
        guard let id = block.subject?.id else { return 0 }
        return sessions.filter { $0.subject?.id == id && Calendar.current.isDateInToday($0.startedAt) }.reduce(0) { $0 + $1.seconds }
    }

    var body: some View {
        WidgetCard(symbol: "timer", title: "Pomodoro") {
            if todaySeconds > 0 {
                Text("\(Fmt.duration(todaySeconds)) today").font(Typo.callout).foregroundStyle(Theme.textTertiary)
            }
        } content: {
            CompactTimer(subjectID: block.subject?.id, ringSize: 112)
                .padding(.horizontal, Space.lg)
                .padding(.bottom, Space.lg)
        }
    }
}

// MARK: - Statistics

struct StatisticsBlockView: View {
    let block: Block
    @Query private var sessions: [FocusSession]
    @Query private var reviews: [ReviewLog]
    @Query private var tasks: [TaskItem]

    var body: some View {
        let summary = ActivitySummary(sessions: sessions, reviews: reviews, tasks: tasks, subjectID: block.subject?.id)
        WidgetCard(symbol: "chart.bar.xaxis", title: "\(block.subject?.name ?? "Study") statistics") {
            if summary.hasAnyData {
                VStack(alignment: .leading, spacing: Space.lg) {
                    let (v, u) = Fmt.hoursValue(summary.totalFocusSeconds)
                    Grid(horizontalSpacing: Space.sm, verticalSpacing: Space.sm) {
                        GridRow {
                            StatTile(value: v, unit: u, caption: "focused")
                            StatTile(value: "\(summary.reviewCount)", unit: "reviews",
                                     caption: summary.accuracy.map { "\(Int(($0 * 100).rounded()))% recalled" } ?? "flashcards")
                        }
                        GridRow {
                            StatTile(value: "\(summary.tasksCompleted)", unit: "tasks", caption: "completed")
                            StatTile(value: "\(Streaks.current(days: summary.studyDays))", unit: "days", caption: "study streak")
                        }
                    }
                    Chart(Calendar.current.days(back: 7), id: \.self) { day in
                        BarMark(x: .value("Day", day, unit: .day), y: .value("Minutes", summary.focusSeconds(on: day) / 60))
                            .foregroundStyle(Theme.ink.opacity(0.85))
                            .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])).foregroundStyle(Theme.border)
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 110)
                    Text("Focus minutes, last 7 days").font(Typo.callout).foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, Space.lg)
                .padding(.bottom, Space.lg)
            } else {
                Text("Statistics for this subject appear once you study it — start a focus session with this subject selected, review its flashcards or complete its tasks.")
                    .font(Typo.body).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.lg)
                    .padding(.bottom, Space.lg)
            }
        }
    }
}

// MARK: - Quiz

struct QuizBlockView: View {
    @Bindable var block: Block
    @Environment(\.modelContext) private var context
    @Query(sort: \Quiz.createdAt, order: .reverse) private var quizzes: [Quiz]
    @State private var editing: Quiz?
    @State private var taking: Quiz?

    var body: some View {
        Group {
            if let quiz = block.quiz {
                WidgetCard(symbol: "questionmark.square.dashed", title: quiz.title.isEmpty ? "Untitled quiz" : quiz.title) {
                    Menu {
                        Button("Edit Questions…") { editing = quiz }
                        Menu("Show a Different Quiz") { choices }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.button).buttonStyle(OSButtonStyle(variant: .ghost, compact: true)).menuIndicator(.hidden).fixedSize()
                } content: {
                    VStack(alignment: .leading, spacing: Space.md) {
                        HStack(alignment: .firstTextBaseline, spacing: Space.xl) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(quiz.questions.count)").font(Typo.numeralSmall)
                                Text("questions").font(Typo.callout).foregroundStyle(Theme.textSecondary)
                            }
                            if let best = quiz.bestScore {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(Int((best * 100).rounded()))%").font(Typo.numeralSmall)
                                    Text("best").font(Typo.callout).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        HStack(spacing: Space.sm) {
                            Button { taking = quiz } label: { Label("Take quiz", systemImage: "play.fill") }
                                .buttonStyle(OSButtonStyle(variant: .primary, compact: true))
                                .disabled(!quiz.questions.contains(where: \.isComplete))
                            Button("Edit") { editing = quiz }
                                .buttonStyle(OSButtonStyle(variant: .secondary, compact: true))
                        }
                    }
                    .padding(.horizontal, Space.lg)
                    .padding(.bottom, Space.lg)
                }
            } else {
                WidgetCard(symbol: "questionmark.square.dashed", title: "Quiz") {
                    BlockSetup(message: "Write a short practice test for this subject and take it as often as you like.") {
                        Button {
                            let quiz = Quiz(title: "", subject: nil)
                            context.insert(quiz)
                            quiz.subject = block.subject
                            block.quiz = quiz
                            editing = quiz
                        } label: { Label("New quiz", systemImage: "plus") }
                            .buttonStyle(OSButtonStyle(variant: .primary, compact: true))
                        if !quizzes.isEmpty {
                            Menu("Use existing quiz") { choices }
                                .menuStyle(.button).buttonStyle(OSButtonStyle(variant: .secondary, compact: true)).fixedSize()
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { QuizEditorView(quiz: $0, lockedSubject: block.subject) }
        .sheet(item: $taking) { QuizRunnerView(quiz: $0) }
    }

    @ViewBuilder private var choices: some View {
        ForEach(quizzes) { q in Button(q.title.isEmpty ? "Untitled quiz" : q.title) { block.quiz = q } }
    }
}
