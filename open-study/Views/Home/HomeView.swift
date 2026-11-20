//
//  HomeView.swift
//  open-study
//
//  Today at a glance (DESIGN.md §13 Home): focus hero, real stats, due tasks,
//  habits, exam countdowns and subjects.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PomodoroEngine.self) private var engine
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]
    @Query private var tasks: [TaskItem]
    @Query private var cards: [Flashcard]
    @Query private var sessions: [FocusSession]
    @Query private var reviews: [ReviewLog]
    @Query(sort: \StudyEvent.start) private var events: [StudyEvent]
    @AppStorage(PrefKey.dailyGoalMinutes) private var goalMinutes = 120
    @State private var review: ReviewSession?

    private var cal: Calendar { .current }

    private var greeting: String {
        switch cal.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var todayFocus: Double {
        sessions.filter { cal.isDateInToday($0.startedAt) }.reduce(0) { $0 + $1.seconds }
    }

    private var dueCards: [Flashcard] { cards.filter { $0.dueDate <= .now }.sorted { $0.dueDate < $1.dueDate } }

    private var todayTasks: [TaskItem] {
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!
        return tasks.filter { !$0.isDone && ($0.dueDate ?? .distantFuture) < end }.sorted(by: TaskOrdering.comparator(.due))
    }

    private var upcomingExams: [StudyEvent] {
        events.filter { $0.kind == .exam && $0.start >= cal.startOfDay(for: .now) }
    }

    private var streak: Int {
        Streaks.current(days: ActivitySummary(sessions: sessions, reviews: reviews, tasks: []).studyDays)
    }

    var body: some View {
        PageScroll {
            PageHeader(title: greeting, subtitle: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .padding(.bottom, Space.xxl)

            HStack(alignment: .top, spacing: Space.lg) {
                FocusHero()
                VStack(alignment: .leading, spacing: Space.md) {
                    statLine(value: "\(Int((todayFocus / 60).rounded()))", unit: "of \(goalMinutes) min today")
                    statLine(value: "\(dueCards.count)", unit: dueCards.count == 1 ? "card due" : "cards due")
                    statLine(value: "\(streak)", unit: streak == 1 ? "day streak" : "day streak")
                }
                .padding(Space.xl)
                .frame(width: 280, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: Radius.window, style: .continuous))
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, Space.x3)

            if subjects.isEmpty && tasks.isEmpty && cards.isEmpty {
                gettingStarted.padding(.bottom, Space.x3)
            }

            HStack(alignment: .top, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.x3) {
                    todaySection
                    HabitsSection()
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: Space.x3) {
                    if !dueCards.isEmpty {
                        VStack(alignment: .leading, spacing: Space.md) {
                            SectionLabel("Flashcards")
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(dueCards.count) card\(dueCards.count == 1 ? "" : "s") ready for review").font(Typo.bodyMedium)
                                    Text("A few minutes now keeps them fresh.").font(Typo.callout).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Button("Review") { review = ReviewSession(title: "Due cards", cards: dueCards) }
                                    .buttonStyle(OSButtonStyle(variant: .secondary, compact: true))
                            }
                            .cardStyle()
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.md) {
                        SectionLabel("Upcoming exams") {
                            Button("Calendar") { router.selection = .calendar }.buttonStyle(OSButtonStyle(variant: .ghost, compact: true))
                        }
                        if upcomingExams.isEmpty {
                            Text("Add exams in Calendar to see a countdown here.").font(Typo.callout).foregroundStyle(Theme.textTertiary)
                        } else {
                            VStack(spacing: Space.md) {
                                ForEach(upcomingExams.prefix(3)) { ExamCountdownRow(exam: $0) }
                            }
                            .cardStyle()
                        }
                    }
                }
                .frame(width: 320, alignment: .topLeading)
            }
            .padding(.bottom, Space.x3)

            if !subjects.isEmpty { subjectsSection }
        }
        .sheet(item: $review) { ReviewView(session: $0) }
    }

    private func statLine(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value).font(Typo.numeral).foregroundStyle(Theme.textPrimary)
            Text(unit).font(Typo.body).foregroundStyle(Theme.textSecondary)
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel("Today") {
                Button("All tasks") { router.selection = .tasks }.buttonStyle(OSButtonStyle(variant: .ghost, compact: true))
            }
            if todayTasks.isEmpty {
                Text(tasks.isEmpty ? "No tasks yet. Add some in Tasks or on a subject page." : "Nothing due today.")
                    .font(Typo.callout).foregroundStyle(Theme.textTertiary)
            } else {
                TaskListCard(tasks: Array(todayTasks.prefix(6)))
                if todayTasks.count > 6 {
                    Text("+\(todayTasks.count - 6) more in Tasks").font(Typo.callout).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private var gettingStarted: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Welcome to Open Study").font(Typo.title)
            Text("Start by creating a subject for each class. Every subject gets its own blank page where you can add notes, flashcards, tasks, PDFs and more.")
                .font(Typo.body).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Button { router.showNewSubject = true } label: { Label("Create a subject", systemImage: "plus") }
                .buttonStyle(.osPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Space.xl)
    }

    private var subjectsSection: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel("Subjects")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Space.md)], spacing: Space.md) {
                ForEach(subjects) { s in
                    SubjectTile(subject: s) { router.selection = .subject(s.id) }
                }
            }
        }
    }
}

private struct SubjectTile: View {
    let subject: Subject
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let open = subject.tasks.filter { !$0.isDone }.count
        let due = subject.decks.flatMap(\.dueCards).count
        Button(action: action) {
            VStack(alignment: .leading, spacing: Space.md) {
                Image(systemName: subject.symbol).font(.system(size: 18)).foregroundStyle(SubjectColor.from(subject.colorKey).color)
                Text(subject.name).font(Typo.headline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text([open > 0 ? "\(open) open task\(open == 1 ? "" : "s")" : nil,
                      due > 0 ? "\(due) card\(due == 1 ? "" : "s") due" : nil].compactMap { $0 }.joined(separator: " · ").ifEmpty("Open page"))
                    .font(Typo.callout).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(hovering ? Theme.borderStrong : Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// Ink hero card: start a focus session or control the running one.
private struct FocusHero: View {
    @Environment(AppRouter.self) private var router
    @Environment(PomodoroEngine.self) private var engine
    @AppStorage(PrefKey.focusMinutes) private var focusMinutes = 25

    var body: some View {
        HStack(alignment: .center, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.md) {
                if engine.isActive {
                    Text(engine.phase.title.uppercased()).font(Typo.label).tracking(1).foregroundStyle(Theme.onInk.opacity(0.6))
                    Text(Fmt.clock(engine.remaining))
                        .font(Typo.displayXL(48))
                        .foregroundStyle(Theme.onInk)
                        .contentTransition(.numericText())
                    if !engine.taskTitle.isEmpty {
                        Text(engine.taskTitle).font(Typo.body).foregroundStyle(Theme.onInk.opacity(0.75)).lineLimit(1)
                    }
                } else {
                    Text("Ready to focus?")
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.onInk)
                    Text("Start a \(focusMinutes)-minute session. Your time is tracked automatically.")
                        .font(Typo.body).foregroundStyle(Theme.onInk.opacity(0.7))
                }
                HStack(spacing: Space.sm) {
                    Button {
                        engine.toggle()
                    } label: {
                        Label(engine.isRunning ? "Pause" : engine.state == .paused ? "Resume" : "Start focus",
                              systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                            .font(Typo.headline)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Theme.onInk, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        withAnimation(Motion.sidebar) { router.selection = .focus }
                    } label: {
                        Text("Focus mode")
                            .font(Typo.headline)
                            .foregroundStyle(Theme.onInk)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Theme.onInk.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, Space.xs)
            }
            Spacer(minLength: 0)
            if engine.isActive {
                ZStack {
                    Circle().stroke(Theme.onInk.opacity(0.15), lineWidth: 2)
                    Circle().trim(from: 0, to: engine.progress)
                        .stroke(Theme.onInk, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: engine.progress)
                }
                .frame(width: 92, height: 92)
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Radius.window, style: .continuous))
    }
}
