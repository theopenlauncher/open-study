//
//  OnboardingSteps.swift
//  open-study
//
//  One question per step. Each step shows what the answer will change —
//  the greeting, the sidebar, the page layout, the countdown — instead of
//  explaining features.
//

import SwiftUI

// MARK: - Shared pieces

private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typo.display)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(Typo.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 28)
    }
}

/// A selectable option card. Selected = `accentSoft` fill + accent border,
/// the same treatment as quiz options (DESIGN.md §13 Quizzes).
private struct ChoiceCard<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .padding(Space.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(selected ? Theme.accentSoft : (hovering ? Theme.hover : Theme.raised),
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : (hovering ? Theme.borderStrong : Theme.border), lineWidth: selected ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.fade, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small "+ Name" suggestion chip.
private struct SuggestionChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                Text(title).font(Typo.callout)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Space.sm)
            .frame(height: 24)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border))
            .contentShape(Rectangle())
            .hoverHighlight(cornerRadius: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(title)")
    }
}

// MARK: - 1 Welcome

struct WelcomeStep: View {
    @Bindable var draft: OnboardingDraft
    let isRerun: Bool
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The title *is* the Home greeting, updating as they type.
            StepHeader(
                title: Greeting.now(name: draft.name),
                subtitle: isRerun
                    ? "Let's revisit how Open Study is set up. Anything you add here joins what you already have. Nothing is removed."
                    : "A few quick questions and Open Study will be set up around the way you study. It takes about a minute, and everything stays on this Mac."
            )
            .animation(nil, value: draft.name)

            FieldRow(label: "What should we call you?") {
                TextField("Name", text: $draft.name, prompt: placeholder("Your first name"))
                    .textFieldStyle(.os)
                    .frame(maxWidth: 320)
                    .focused($focused)
                    .onSubmit(onSubmit)
            }
            Text("Only used to greet you on Home.")
                .font(Typo.callout).foregroundStyle(Theme.textTertiary)
                .padding(.top, Space.sm)
        }
        .onAppear { focused = true }
    }
}

// MARK: - 2 Subjects

struct SubjectsStep: View {
    @Bindable var draft: OnboardingDraft
    let onSubmitEmpty: () -> Void
    @FocusState private var focused: Bool

    private var remainingSuggestions: [String] { SubjectGuess.suggestions.filter { !draft.hasSubject(named: $0) } }
    private var canAdd: Bool {
        let t = draft.pendingSubject.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && !draft.hasSubject(named: t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "What are you studying?",
                       subtitle: "Add each class or course. They appear in your sidebar straight away, each with a page of its own.")

            HStack(spacing: Space.sm) {
                TextField("Subject", text: $draft.pendingSubject, prompt: placeholder("e.g. Organic chemistry"))
                    .textFieldStyle(.os)
                    .focused($focused)
                    .onSubmit(submit)
                Button("Add", action: add)
                    .buttonStyle(.osSecondary)
                    .disabled(!canAdd)
            }
            .frame(maxWidth: 420)

            if !draft.pendingSubject.isEmpty && draft.hasSubject(named: draft.pendingSubject) {
                Text("“\(draft.pendingSubject.trimmingCharacters(in: .whitespaces))” is already on your list.")
                    .font(Typo.callout).foregroundStyle(Theme.textTertiary)
                    .padding(.top, Space.sm)
            }

            if !remainingSuggestions.isEmpty {
                FlowLayout {
                    ForEach(remainingSuggestions, id: \.self) { name in
                        SuggestionChip(title: name) { withAnimation(Motion.fade) { draft.addSubject(name) } }
                    }
                }
                .padding(.top, Space.md)
            }

            if !draft.subjects.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(draft.subjects.enumerated()), id: \.element.id) { i, subject in
                        if i > 0 { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 48) }
                        DraftSubjectRow(draft: draft, subject: subject)
                    }
                }
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
                .padding(.top, Space.xxl)

                Text("Click an icon to change it or the colour.")
                    .font(Typo.callout).foregroundStyle(Theme.textTertiary)
                    .padding(.top, Space.sm)
            }
        }
        .animation(Motion.fade, value: draft.subjects)
        .onAppear { focused = true }
    }

    private func submit() {
        if draft.pendingSubject.trimmingCharacters(in: .whitespaces).isEmpty { onSubmitEmpty() } else { add() }
    }

    private func add() {
        guard canAdd else { return }
        withAnimation(Motion.fade) { draft.addSubject(draft.pendingSubject) }
        draft.pendingSubject = ""
        focused = true
    }
}

private struct DraftSubjectRow: View {
    @Bindable var draft: OnboardingDraft
    let subject: DraftSubject
    @State private var editing = false

    var body: some View {
        HStack(spacing: Space.md) {
            Button { editing = true } label: {
                Image(systemName: subject.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(SubjectColor.from(subject.colorKey).color)
                    .frame(width: 28, height: 28)
                    .background(SubjectColor.from(subject.colorKey).color.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: Radius.icon, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(subject.isExisting)
            .help(subject.isExisting ? subject.name : "Change icon and colour")
            .accessibilityLabel("Change icon and colour for \(subject.name)")
            .popover(isPresented: $editing, arrowEdge: .bottom) {
                SubjectEditor(subject: nil, initial: (subject.name, subject.symbol, subject.colorKey)) { name, symbol, color in
                    if let i = draft.subjects.firstIndex(where: { $0.id == subject.id }) {
                        draft.subjects[i].name = name
                        draft.subjects[i].symbol = symbol
                        draft.subjects[i].colorKey = color
                    }
                    editing = false
                }
            }

            Text(subject.name).font(Typo.bodyMedium).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Spacer()
            if subject.isExisting {
                Text("Already in your sidebar").font(Typo.callout).foregroundStyle(Theme.textTertiary)
            } else {
                IconButton(symbol: "xmark", help: "Remove \(subject.name)", size: 24) {
                    withAnimation(Motion.fade) { draft.removeSubject(subject.id) }
                }
            }
        }
        .padding(.horizontal, Space.md)
        .frame(height: 44)
    }
}

// MARK: - 3 Tools

struct ToolsStep: View {
    @Bindable var draft: OnboardingDraft

    private var previewSubject: DraftSubject? { draft.newSubjects.first ?? draft.subjects.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "How do you like to study?",
                       subtitle: "Pick the tools you'll actually use. Every new subject page starts with them in place: empty, ready for your own material.")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.md), GridItem(.flexible(), spacing: Space.md)], spacing: Space.md) {
                ForEach(StudyTool.allCases) { tool in
                    let on = draft.tools.contains(tool)
                    ChoiceCard(selected: on) {
                        if on { draft.tools.remove(tool) } else { draft.tools.insert(tool) }
                    } content: {
                        HStack(alignment: .top, spacing: Space.md) {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 14))
                                .foregroundStyle(on ? Theme.accent : Theme.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(on ? Theme.raised : Theme.muted, in: RoundedRectangle(cornerRadius: Radius.icon, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tool.title).font(Typo.headline).foregroundStyle(Theme.textPrimary)
                                Text(tool.subtitle).font(Typo.callout).foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            Text("Notes are always there: just start typing on any page.")
                .font(Typo.callout).foregroundStyle(Theme.textTertiary)
                .padding(.top, Space.md)

            if !draft.newSubjects.isEmpty {
                SectionLabel("\(previewSubject?.name ?? "Your") page will start like this")
                    .padding(.top, Space.x3)
                    .padding(.bottom, Space.md)
                PagePreview(subject: previewSubject, blocks: draft.starterBlocks)
            }
        }
        .animation(Motion.fade, value: draft.tools)
    }
}

/// A miniature subject page: header plus outlines of the starting blocks.
private struct PagePreview: View {
    let subject: DraftSubject?
    let blocks: [(kind: BlockKind, width: Double)]

    /// Packs blocks into rows while their widths sum to ≤ 1, like the real page.
    private var rows: [[(kind: BlockKind, width: Double)]] {
        var rows: [[(kind: BlockKind, width: Double)]] = []
        var current: [(kind: BlockKind, width: Double)] = []
        var sum = 0.0
        for b in blocks {
            if sum + b.width > 1.001, !current.isEmpty { rows.append(current); current = []; sum = 0 }
            current.append(b); sum += b.width
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Image(systemName: subject?.symbol ?? "book.closed")
                    .font(.system(size: 16))
                    .foregroundStyle(SubjectColor.from(subject?.colorKey ?? "slate").color)
                Text(subject?.name ?? "Subject")
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
            }
            if blocks.isEmpty {
                Text("A blank page. Press / to add blocks whenever you need them.")
                    .font(Typo.callout).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Space.sm) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, b in
                            HStack(spacing: 6) {
                                Image(systemName: b.kind.symbol).font(.system(size: 11))
                                Text(b.kind.title).font(Typo.callout)
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, Space.sm)
                            .frame(maxWidth: .infinity, minHeight: b.kind == .pdf ? 52 : 36, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border))
                        }
                    }
                }
                Text("Type / for blocks").font(Typo.callout).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 4 Rhythm

struct RhythmStep: View {
    @Bindable var draft: OnboardingDraft

    private var goalOptions: [(Int, String)] {
        var options = [(30, "30 min"), (60, "1 hr"), (90, "1.5 hr"), (120, "2 hr"), (180, "3 hr"), (240, "4 hr")]
        if !options.contains(where: { $0.0 == draft.dailyGoal }) {
            options.append((draft.dailyGoal, "\(draft.dailyGoal) min"))
            options.sort { $0.0 < $1.0 }
        }
        return options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Find your rhythm",
                       subtitle: "How long can you focus before you need a break? This sets your focus timer.")

            HStack(spacing: Space.md) {
                ForEach(FocusRhythm.allCases) { r in
                    let on = draft.keepCustomFocus == nil && draft.rhythm == r
                    ChoiceCard(selected: on) {
                        draft.rhythm = r
                        draft.keepCustomFocus = nil
                    } content: {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text(r.title).font(Typo.headline).foregroundStyle(Theme.textPrimary)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(r.focus)").font(Typo.numeral).foregroundStyle(Theme.textPrimary)
                                Text("min focus").font(Typo.body).foregroundStyle(Theme.textSecondary)
                            }
                            Text("\(r.shortBreak)-min breaks").font(Typo.callout).foregroundStyle(Theme.textSecondary)
                            Text(r.detail).font(Typo.callout).foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if let custom = draft.keepCustomFocus {
                Text("You currently use \(custom)-minute sessions\(draft.customShortBreak.map { " with \($0)-minute breaks" } ?? ""). Pick a rhythm to change that, or continue to keep your timer as it is.")
                    .font(Typo.callout).foregroundStyle(Theme.textTertiary)
                    .padding(.top, Space.md)
            }

            SectionLabel("Daily focus goal")
                .padding(.top, Space.x3)
                .padding(.bottom, Space.md)
            OSSegmented(options: goalOptions, selection: $draft.dailyGoal)
                .fixedSize()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(draft.sessionsForGoal)").font(Typo.numeral).foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(draft.sessionsForGoal == 1 ? "focus session a day" : "focus sessions a day")
                    .font(Typo.body).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("at \(draft.focusMinutes) minutes each")
                    .font(Typo.callout).foregroundStyle(Theme.textTertiary)
            }
            .padding(Space.lg)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(.top, Space.lg)
            .animation(Motion.fade, value: draft.sessionsForGoal)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - 5 Exams

struct ExamsStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Any exams coming up?",
                       subtitle: "Add them and Home counts down the days. They also go on your calendar. Skip this if nothing is scheduled yet.")

            if !draft.exams.isEmpty {
                VStack(spacing: 0) {
                    // Bindings look rows up by id, so removing a row while its
                    // field is being edited can't index past the end of the array.
                    ForEach(Array(draft.exams.enumerated()), id: \.element.id) { i, exam in
                        if i > 0 { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 40) }
                        ExamRow(draft: draft, exam: binding(for: exam))
                    }
                }
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
                .padding(.bottom, Space.md)
            }

            Button { addExam() } label: { Label(draft.exams.isEmpty ? "Add an exam" : "Add another", systemImage: "plus") }
                .buttonStyle(.osSecondary)
        }
        .animation(Motion.fade, value: draft.exams)
    }

    private func binding(for exam: DraftExam) -> Binding<DraftExam> {
        Binding(
            get: { draft.exams.first { $0.id == exam.id } ?? exam },
            set: { new in
                if let i = draft.exams.firstIndex(where: { $0.id == exam.id }) { draft.exams[i] = new }
            }
        )
    }

    private func addExam() {
        // Suggest the next subject that doesn't have an exam yet.
        let taken = Set(draft.exams.compactMap(\.subjectID))
        var exam = DraftExam()
        exam.subjectID = draft.subjects.first { !taken.contains($0.id) }?.id
        draft.exams.append(exam)
    }
}

private struct ExamRow: View {
    @Bindable var draft: OnboardingDraft
    @Binding var exam: DraftExam

    private var daysAway: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: exam.date)).day ?? 0
    }

    private var countdown: String {
        switch daysAway {
        case ..<1: "Today"
        case 1: "Tomorrow"
        default: "In \(daysAway) days"
        }
    }

    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "flag.fill").font(.system(size: 12)).foregroundStyle(Theme.danger).frame(width: 16)
            TextField("Exam name", text: $exam.title,
                      prompt: placeholder(draft.subject(exam.subjectID).map { "\($0.name) exam" } ?? "Exam name"))
                .textFieldStyle(.os)
            Picker("Subject", selection: $exam.subjectID) {
                Text("No subject").tag(UUID?.none)
                ForEach(draft.subjects) { s in Text(s.name).tag(UUID?.some(s.id)) }
            }
            .labelsHidden()
            .frame(width: 140)
            DatePicker("Date", selection: $exam.date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                .datePickerStyle(.field)
                .labelsHidden()
                .fixedSize()
            Text(countdown)
                .font(Typo.callout.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                .frame(width: 72, alignment: .trailing)
            IconButton(symbol: "xmark", help: "Remove exam", size: 24) {
                // Read the id first: `exam` is looked up in `draft.exams`, which
                // `removeAll` is mutating, and overlapping access would trap.
                let id = exam.id
                draft.exams.removeAll { $0.id == id }
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }
}

// MARK: - 6 Habits

struct HabitsStep: View {
    @Bindable var draft: OnboardingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Which habits do you want to build?",
                       subtitle: "Pick a few to tick off on Home each day. Small and daily beats big and rare.")

            VStack(spacing: 0) {
                ForEach(Array(draft.habitSuggestions.enumerated()), id: \.element.id) { i, habit in
                    if i > 0 { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44) }
                    let on = draft.isHabitSelected(habit)
                    Button { toggle(habit) } label: {
                        HStack(spacing: Space.md) {
                            SquareCheckbox(isOn: on) { toggle(habit) }
                            Image(systemName: habit.symbol).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).frame(width: 18)
                            Text(habit.name).font(Typo.body).foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, Space.md)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                        .hoverHighlight(cornerRadius: 0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))

            HStack(spacing: Space.sm) {
                TextField("Habit", text: $draft.pendingHabit, prompt: placeholder("Add your own, e.g. Practise vocabulary"))
                    .textFieldStyle(.os)
                    .onSubmit(add)
                Button("Add", action: add)
                    .buttonStyle(.osSecondary)
                    .disabled(draft.pendingHabit.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(maxWidth: 420)
            .padding(.top, Space.md)

            if !draft.existingHabitNames.isEmpty {
                Text("Habits you already track stay as they are.")
                    .font(Typo.callout).foregroundStyle(Theme.textTertiary)
                    .padding(.top, Space.sm)
            }
        }
        .animation(Motion.fade, value: draft.habitSuggestions)
    }

    private func toggle(_ habit: DraftHabit) {
        draft.toggleHabit(habit)
    }

    private func add() {
        draft.addCustomHabit(draft.pendingHabit)
        draft.pendingHabit = ""
    }
}

// MARK: - 7 Look & privacy

struct LookStep: View {
    @Bindable var draft: OnboardingDraft
    /// Applies the appearance live so the user sees it immediately.
    let onAppearance: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: "Make it yours",
                       subtitle: "How Open Study looks, and what it may do in the background. Change any of it later in Settings.")

            SectionLabel("Appearance").padding(.bottom, Space.md)
            HStack(spacing: Space.md) {
                ForEach([("light", "Light"), ("dark", "Dark"), ("system", "Match system")], id: \.0) { key, title in
                    ChoiceCard(selected: draft.appearance == key) {
                        draft.appearance = key
                        onAppearance(key)
                    } content: {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            AppearanceSwatch(mode: key)
                            Text(title).font(Typo.headline).foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            SectionLabel("Focus timer").padding(.top, Space.x3).padding(.bottom, Space.md)
            OSCard {
                SwitchRow(title: "Tell me when a focus session ends",
                          detail: "macOS asks for permission when you finish setup.",
                          isOn: $draft.notifications)
            }

            SectionLabel("Privacy").padding(.top, Space.x3).padding(.bottom, Space.md)
            OSCard {
                SwitchRow(title: "Share anonymous usage data",
                          detail: "Counts and on/off details plus crash reports, to help improve Open Study. Your notes, card text, task titles, names and files never leave this Mac.",
                          isOn: $draft.analytics)
            }
        }
    }
}

/// Label + detail on the left, a native switch on the trailing edge.
private struct SwitchRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.bodyMedium).foregroundStyle(Theme.textPrimary)
                Text(detail).font(Typo.callout).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden()
        }
    }
}

/// A tiny window drawn from real tokens in a forced colour scheme.
private struct AppearanceSwatch: View {
    let mode: String

    var body: some View {
        Group {
            switch mode {
            case "light": window.environment(\.colorScheme, .light)
            case "dark": window.environment(\.colorScheme, .dark)
            default:
                // Left half light, right half dark.
                ZStack {
                    window.environment(\.colorScheme, .light)
                    window.environment(\.colorScheme, .dark)
                        .mask(HStack(spacing: 0) { Color.clear; Color.black })
                }
            }
        }
        .frame(height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private var window: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Theme.sidebarActive).frame(height: 6)
                Capsule().fill(Theme.border).frame(width: 18, height: 4)
                Capsule().fill(Theme.border).frame(width: 14, height: 4)
            }
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Theme.textPrimary.opacity(0.8)).frame(width: 30, height: 5)
                Capsule().fill(Theme.border).frame(height: 4)
                RoundedRectangle(cornerRadius: 3).fill(Theme.ink).frame(height: 14)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Theme.canvas)
    }
}

// MARK: - 8 Ready

struct ReadyStep: View {
    let draft: OnboardingDraft
    let isRerun: Bool

    private var title: String {
        if isRerun { return "Here's what will be added" }
        return draft.trimmedName.isEmpty ? "Your workspace is ready" : "Your workspace is ready, \(draft.trimmedName)"
    }

    private var nextExam: DraftExam? { draft.exams.min { $0.date < $1.date } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepHeader(title: title,
                       subtitle: "This is how Open Study will be set up when you open it. You can change any of it later from the sidebar or Settings.")

            VStack(spacing: 0) {
                row("square.stack", "Subjects") {
                    if draft.newSubjects.isEmpty {
                        Text("None yet. Add them from the sidebar.").foregroundStyle(Theme.textTertiary)
                    } else {
                        FlowLayout(spacing: Space.sm, lineSpacing: Space.xs) {
                            ForEach(draft.newSubjects) { s in
                                HStack(spacing: 5) {
                                    SubjectDot(colorKey: s.colorKey, size: 7)
                                    Text(s.name).font(Typo.callout).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
                divider
                row("square.grid.2x2", "Each page starts with") {
                    Text(draft.tools.isEmpty ? "Nothing — blank pages" : StudyTool.allCases.filter { draft.tools.contains($0) }.map(\.title).joined(separator: ", "))
                        .foregroundStyle(draft.tools.isEmpty ? Theme.textTertiary : Theme.textSecondary)
                }
                divider
                row("timer", "Focus") {
                    Text("\(draft.focusMinutes)-minute sessions · \(Fmt.duration(Double(draft.dailyGoal * 60))) a day")
                        .foregroundStyle(Theme.textSecondary)
                }
                divider
                row("flag", "Exams") {
                    if let nextExam {
                        let name = nextExam.title.trimmingCharacters(in: .whitespaces)
                            .ifEmpty(draft.subject(nextExam.subjectID).map { "\($0.name) exam" } ?? "Exam")
                        Text(draft.exams.count == 1 ? name : "\(name) and \(draft.exams.count - 1) more")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("None").foregroundStyle(Theme.textTertiary)
                    }
                }
                divider
                row("checkmark.circle", "Daily habits") {
                    Text(draft.chosenHabits.isEmpty ? "None" : draft.chosenHabits.map(\.name).joined(separator: ", "))
                        .foregroundStyle(draft.chosenHabits.isEmpty ? Theme.textTertiary : Theme.textSecondary)
                }
            }
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44)
    }

    private func row<Value: View>(_ symbol: String, _ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Theme.textSecondary).frame(width: 20)
            Text(label).font(Typo.bodyMedium).foregroundStyle(Theme.textPrimary).frame(width: 150, alignment: .leading)
            value().font(Typo.body).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .combine)
    }
}
