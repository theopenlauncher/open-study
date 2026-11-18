//
//  CalendarView.swift
//  open-study
//
//  Month calendar of study events, exams and task deadlines, with exam
//  countdowns. Entirely local — no calendar accounts.
//

import SwiftUI
import SwiftData

private enum CalendarItem: Identifiable {
    case event(StudyEvent)
    case task(TaskItem)

    var id: String {
        switch self {
        case .event(let e): "e-\(e.id)"
        case .task(let t): "t-\(t.id)"
        }
    }
}

struct EventDraft: Identifiable {
    let id = UUID()
    let event: StudyEvent?
    let day: Date
    var kind: EventKind = .study
}

struct CalendarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StudyEvent.start) private var events: [StudyEvent]
    @Query private var tasks: [TaskItem]

    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now))!
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var draft: EventDraft?

    private var cal: Calendar { .current }

    private var gridDays: [Date] {
        let firstWeekday = cal.component(.weekday, from: month)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -leading, to: month)!
        let daysInMonth = cal.range(of: .day, in: .month, for: month)!.count
        let cells = Int(ceil(Double(leading + daysInMonth) / 7.0)) * 7
        return (0..<cells).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func items(on day: Date) -> [CalendarItem] {
        let evs = events.filter { cal.isDate($0.start, inSameDayAs: day) }.map(CalendarItem.event)
        let ts = tasks.filter { t in t.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }.map(CalendarItem.task)
        return evs + ts
    }

    private var upcomingExams: [StudyEvent] {
        let today = cal.startOfDay(for: .now)
        return events.filter { $0.kind == .exam && $0.start >= today }.sorted { $0.start < $1.start }
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 1000
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.bottom, Space.xl)
                    if wide {
                        HStack(alignment: .top, spacing: Space.xxl) {
                            monthGrid
                            rail.frame(width: 300)
                        }
                    } else {
                        monthGrid
                        rail.padding(.top, Space.xxl)
                    }
                }
                .padding(.horizontal, geo.size.width < 900 ? Space.x3 : Space.x5)
                .padding(.top, 36)
                .padding(.bottom, Space.x5)
            }
        }
        .sheet(item: $draft) { d in EventEditor(draft: d) }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(month.formatted(.dateTime.month(.wide).year())).font(Typo.display)
                Text(upcomingExams.first.map { "Next exam: \($0.title) in \(daysUntil($0.start))" } ?? "Plan study sessions, exams and deadlines.")
                    .font(Typo.body).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HStack(spacing: Space.xs) {
                IconButton(symbol: "chevron.left", help: "Previous month") { shiftMonth(-1) }
                Button("Today") {
                    month = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
                    selectedDay = cal.startOfDay(for: .now)
                }
                .buttonStyle(OSButtonStyle(variant: .secondary, compact: true))
                .keyboardShortcut("t", modifiers: .command)
                IconButton(symbol: "chevron.right", help: "Next month") { shiftMonth(1) }
                Button { draft = EventDraft(event: nil, day: selectedDay) } label: { Label("New event", systemImage: "plus") }
                    .buttonStyle(.osPrimary)
                    .padding(.leading, Space.sm)
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }

    private func shiftMonth(_ delta: Int) {
        withAnimation(Motion.fade) { month = cal.date(byAdding: .month, value: delta, to: month)! }
    }

    private var monthGrid: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        let days = gridDays
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                    Text(s).font(Typo.label).foregroundStyle(Theme.textTertiary).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(days, id: \.self) { day in
                    DayCell(day: day, inMonth: cal.isDate(day, equalTo: month, toGranularity: .month),
                            isSelected: cal.isDate(day, inSameDayAs: selectedDay), items: items(on: day))
                        .onTapGesture(count: 2) { draft = EventDraft(event: nil, day: day) }
                        .onTapGesture { selectedDay = cal.startOfDay(for: day) }
                }
            }
        }
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(selectedDay.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                    IconButton(symbol: "plus", help: "Add event on this day", size: 22) {
                        draft = EventDraft(event: nil, day: selectedDay)
                    }
                }
                let dayItems = items(on: selectedDay)
                if dayItems.isEmpty {
                    Text("Nothing planned. Double-click a day or use + to add a study session or exam.")
                        .font(Typo.callout).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: Space.xs) {
                        ForEach(dayItems) { item in agendaRow(item) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel("Upcoming exams")
                if upcomingExams.isEmpty {
                    Text("Add an event with the type “Exam” to see a countdown here.")
                        .font(Typo.callout).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: Space.sm) {
                        ForEach(upcomingExams.prefix(6)) { exam in
                            ExamCountdownRow(exam: exam)
                                .onTapGesture { draft = EventDraft(event: exam, day: exam.start) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func agendaRow(_ item: CalendarItem) -> some View {
        switch item {
        case .event(let e):
            Button { draft = EventDraft(event: e, day: e.start) } label: {
                HStack(alignment: .top, spacing: Space.sm) {
                    Image(systemName: e.kind.symbol).font(.system(size: 12))
                        .foregroundStyle(e.kind == .exam ? Theme.danger : (e.subject.map { SubjectColor.from($0.colorKey).color } ?? Theme.textSecondary))
                        .frame(width: 16).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(Typo.bodyMedium).foregroundStyle(Theme.textPrimary)
                        Text(e.isAllDay ? "All day" : "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                            .font(Typo.callout).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    SubjectChip(subject: e.subject)
                }
                .padding(Space.sm)
                .contentShape(Rectangle())
                .hoverHighlight()
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Edit…") { draft = EventDraft(event: e, day: e.start) }
                Button("Delete", role: .destructive) { context.delete(e) }
            }
        case .task(let t):
            HStack(spacing: Space.sm) {
                TaskCheckbox(isOn: t.isDone) { withAnimation { t.toggle() } }
                Text(t.title).font(Typo.body)
                    .foregroundStyle(t.isDone ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(t.isDone)
                Spacer()
                SubjectChip(subject: t.subject)
            }
            .padding(Space.sm)
        }
    }

    private func daysUntil(_ date: Date) -> String {
        let d = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
        return d == 0 ? "today" : d == 1 ? "1 day" : "\(d) days"
    }
}

private struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let items: [CalendarItem]
    @State private var hovering = false

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        VStack(alignment: .leading, spacing: 3) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(Typo.callout.weight(isToday ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isToday ? Theme.onInk : (inMonth ? Theme.textPrimary : Theme.textTertiary))
                .frame(width: 22, height: 22)
                .background(isToday ? Theme.ink : .clear, in: Circle())
            ForEach(items.prefix(3)) { item in chip(item) }
            if items.count > 3 {
                Text("+\(items.count - 3) more").font(.system(size: 10)).foregroundStyle(Theme.textTertiary).padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(isSelected ? Theme.accentSoft : (hovering ? Theme.hover : .clear))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
        .opacity(inMonth ? 1 : 0.55)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(items.count) items")
    }

    @ViewBuilder private func chip(_ item: CalendarItem) -> some View {
        switch item {
        case .event(let e):
            let color = e.subject.map { SubjectColor.from($0.colorKey).color } ?? Theme.textSecondary
            HStack(spacing: 3) {
                if e.kind == .exam {
                    Image(systemName: "flag.fill").font(.system(size: 8)).foregroundStyle(Theme.danger)
                }
                Text(e.title).lineLimit(1)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((e.kind == .exam ? Theme.danger : color).opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .task(let t):
            HStack(spacing: 3) {
                Circle().strokeBorder(Theme.textTertiary, lineWidth: 1).frame(width: 7, height: 7)
                Text(t.title).lineLimit(1).strikethrough(t.isDone)
            }
            .font(.system(size: 11))
            .foregroundStyle(t.isDone ? Theme.textTertiary : Theme.textSecondary)
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ExamCountdownRow: View {
    let exam: StudyEvent

    var body: some View {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                   to: Calendar.current.startOfDay(for: exam.start)).day ?? 0
        HStack(spacing: Space.md) {
            VStack(spacing: 0) {
                Text("\(days)").font(Typo.numeralSmall).foregroundStyle(days <= 7 ? Theme.danger : Theme.textPrimary)
                Text(days == 1 ? "day" : "days").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 48, height: 48)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(exam.title).font(Typo.bodyMedium).lineLimit(1)
                Text(exam.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(Typo.callout).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            SubjectChip(subject: exam.subject)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editor

struct EventEditor: View {
    let draft: EventDraft
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    @State private var title = ""
    @State private var kind: EventKind = .study
    @State private var subjectID: UUID?
    @State private var day = Date()
    @State private var start = Date()
    @State private var end = Date()
    @State private var allDay = false
    @State private var notes = ""
    @State private var confirmDelete = false

    var body: some View {
        SheetScaffold(title: draft.event == nil ? "New event" : "Edit event", width: 460) {
            VStack(alignment: .leading, spacing: Space.lg) {
                TextField(kind == .exam ? "Exam name, e.g. Chemistry Paper 1" : "Title, e.g. Revise thermodynamics", text: $title)
                    .textFieldStyle(.os)
                Picker("Type", selection: $kind) {
                    ForEach(EventKind.allCases) { k in Text(k.title).tag(k) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: Space.lg) {
                    FieldRow(label: "Date") {
                        DatePicker("Date", selection: $day, displayedComponents: .date).labelsHidden().datePickerStyle(.field)
                    }
                    FieldRow(label: "Subject") {
                        Picker("Subject", selection: $subjectID) {
                            Text("None").tag(UUID?.none)
                            ForEach(subjects) { s in Text(s.name).tag(UUID?.some(s.id)) }
                        }
                        .labelsHidden()
                    }
                }
                Toggle("All day", isOn: $allDay).toggleStyle(.checkbox)
                if !allDay {
                    HStack(spacing: Space.lg) {
                        FieldRow(label: "Starts") {
                            DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute).labelsHidden()
                        }
                        FieldRow(label: "Ends") {
                            DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute).labelsHidden()
                        }
                    }
                    if combined(end) <= combined(start) {
                        Text("The end time should be after the start time.").font(Typo.callout).foregroundStyle(Theme.warning)
                    }
                }
                TextField("Notes", text: $notes, axis: .vertical).textFieldStyle(.os).lineLimit(2...5)
            }
        } footer: {
            if draft.event != nil {
                Button("Delete", role: .destructive) { confirmDelete = true }.buttonStyle(.osDestructive)
            }
            Spacer()
            Button("Cancel") { dismiss() }.buttonStyle(.osGhost).keyboardShortcut(.cancelAction)
            Button("Save", action: save).buttonStyle(.osPrimary).keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Event", role: .destructive) {
                if let e = draft.event { context.delete(e) }
                try? context.save()
                dismiss()
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        let cal = Calendar.current
        if let e = draft.event {
            title = e.title
            kind = e.kind
            subjectID = e.subject?.id
            day = e.start
            start = e.start
            end = e.end
            allDay = e.isAllDay
            notes = e.notes
        } else {
            kind = draft.kind
            day = draft.day
            let hour = cal.component(.hour, from: .now) + 1
            start = cal.date(bySettingHour: min(hour, 22), minute: 0, second: 0, of: draft.day) ?? draft.day
            end = start.addingTimeInterval(3600)
        }
    }

    private func combined(_ time: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    private func save() {
        let cal = Calendar.current
        let s = allDay ? cal.startOfDay(for: day) : combined(start)
        var e = allDay ? cal.date(byAdding: .day, value: 1, to: s)!.addingTimeInterval(-60) : combined(end)
        if e <= s { e = s.addingTimeInterval(3600) }
        let subject = subjects.first { $0.id == subjectID }
        let event: StudyEvent
        if let existing = draft.event {
            event = existing
        } else {
            event = StudyEvent(title: "", kind: kind, start: s, end: e)
            context.insert(event)
        }
        event.title = title.trimmingCharacters(in: .whitespaces)
        event.kind = kind
        event.start = s
        event.end = e
        event.isAllDay = allDay
        event.notes = notes
        event.subject = subject
        try? context.save()
        dismiss()
    }
}
