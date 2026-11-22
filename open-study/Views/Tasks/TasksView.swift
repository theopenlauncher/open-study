//
//  TasksView.swift
//  open-study
//
//  Global task overview across all subjects (DESIGN.md §13 Tasks).
//

import SwiftUI
import SwiftData
import PostHog

enum TaskFilter: String, CaseIterable { case open, completed, all }
enum TaskSort: String, CaseIterable {
    case due, priority, created
    var title: String {
        switch self {
        case .due: "Due date"
        case .priority: "Priority"
        case .created: "Date added"
        }
    }
}

struct TasksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    @AppStorage("tasks.filter") private var filterRaw = TaskFilter.open.rawValue
    @AppStorage("tasks.sort") private var sortRaw = TaskSort.due.rawValue
    @State private var subjectFilter: UUID?

    private var filter: TaskFilter { TaskFilter(rawValue: filterRaw) ?? .open }
    private var sort: TaskSort { TaskSort(rawValue: sortRaw) ?? .due }

    private var visible: [TaskItem] {
        tasks
            .filter { t in
                switch filter {
                case .open: !t.isDone
                case .completed: t.isDone
                case .all: true
                }
            }
            .filter { subjectFilter == nil || $0.subject?.id == subjectFilter }
            .sorted(by: TaskOrdering.comparator(sort))
    }

    private var groups: [(String, [TaskItem])] {
        guard sort == .due, filter != .completed else { return [("", visible)] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var overdue: [TaskItem] = [], todayList: [TaskItem] = [], upcoming: [TaskItem] = [], none: [TaskItem] = [], done: [TaskItem] = []
        for t in visible {
            if t.isDone { done.append(t); continue }
            guard let d = t.dueDate else { none.append(t); continue }
            let day = cal.startOfDay(for: d)
            if day < today { overdue.append(t) } else if day == today { todayList.append(t) } else { upcoming.append(t) }
        }
        return [("Overdue", overdue), ("Today", todayList), ("Upcoming", upcoming), ("No date", none), ("Completed", done)]
            .filter { !$0.1.isEmpty }
    }

    private var openCount: Int { tasks.filter { !$0.isDone }.count }
    private var dueTodayCount: Int {
        tasks.filter { !$0.isDone && ($0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false) }.count
    }

    var body: some View {
        PageScroll {
            PageHeader(title: "Tasks", subtitle: subtitle)
                .padding(.bottom, Space.xxl)

            NewTaskBar(subjects: subjects, defaultSubjectID: subjectFilter) { task in
                context.insert(task)
                do {
                    try context.save()
                    PostHogSDK.shared.capture("task_created", properties: [
                        "has_due_date": task.dueDate != nil,
                        "has_subject": task.subject != nil,
                        "priority": task.priorityRaw,
                    ])
                } catch {}
            }
            .padding(.bottom, Space.lg)

            HStack(spacing: Space.sm) {
                OSSegmented(options: [(TaskFilter.open.rawValue, "Open"), (TaskFilter.completed.rawValue, "Completed"), (TaskFilter.all.rawValue, "All")],
                            selection: $filterRaw)
                Spacer()
                GhostMenu(title: subjectFilter.flatMap { id in subjects.first { $0.id == id }?.name } ?? "All subjects",
                          symbol: "line.3.horizontal.decrease") {
                    Button("All subjects") { subjectFilter = nil }
                    Divider()
                    ForEach(subjects) { s in Button(s.name) { subjectFilter = s.id } }
                }
                GhostMenu(title: "Sort: \(sort.title)", symbol: "arrow.up.arrow.down") {
                    ForEach(TaskSort.allCases, id: \.self) { s in
                        Button(s.title) { sortRaw = s.rawValue }
                    }
                }
            }
            .padding(.bottom, Space.lg)

            if visible.isEmpty {
                OSCard {
                    EmptyStateView(
                        symbol: filter == .completed ? "checkmark.circle" : "checklist",
                        title: emptyTitle,
                        message: emptyMessage
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    ForEach(groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: Space.sm) {
                            if !group.0.isEmpty {
                                SectionLabel(group.0) {
                                    Text("\(group.1.count)").font(Typo.callout.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                                }
                            }
                            TaskListCard(tasks: group.1)
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        if tasks.isEmpty { return "Plan your work across every subject." }
        var parts = ["\(openCount) open"]
        if dueTodayCount > 0 { parts.append("\(dueTodayCount) due today") }
        return parts.joined(separator: " · ")
    }

    private var emptyTitle: String {
        switch filter {
        case .open: tasks.isEmpty ? "No tasks yet" : "All caught up"
        case .completed: "Nothing completed yet"
        case .all: "No tasks yet"
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .open: tasks.isEmpty ? "Add a task above. Give it a due date and subject to see it on your calendar and subject pages." : "Every open task in this view is done. Enjoy the calm."
        case .completed: "Tasks you tick off will appear here."
        case .all: "Add a task above to get started."
        }
    }
}

enum TaskOrdering {
    static func comparator(_ sort: TaskSort) -> (TaskItem, TaskItem) -> Bool {
        { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            switch sort {
            case .due:
                let da = a.dueDate ?? .distantFuture, db = b.dueDate ?? .distantFuture
                if da != db { return da < db }
                return a.priorityRaw > b.priorityRaw
            case .priority:
                if a.priorityRaw != b.priorityRaw { return a.priorityRaw > b.priorityRaw }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            case .created:
                return a.createdAt > b.createdAt
            }
        }
    }
}

/// Bordered card with separators between task rows.
struct TaskListCard: View {
    let tasks: [TaskItem]
    var showSubject = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                if index > 0 { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44) }
                TaskRow(task: task, showSubject: showSubject)
                    .padding(.horizontal, Space.md)
            }
        }
        .padding(.vertical, Space.xs)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
    }
}

struct TaskRow: View {
    @Bindable var task: TaskItem
    var showSubject = true
    @Environment(\.modelContext) private var context
    @State private var showEditor = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: Space.md) {
            TaskCheckbox(isOn: task.isDone) {
                withAnimation(Motion.fade) { task.toggle() }
            }
            TextField("Task", text: $task.title)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .foregroundStyle(task.isDone ? Theme.textTertiary : Theme.textPrimary)
                .strikethrough(task.isDone, color: Theme.textTertiary)
            Spacer(minLength: Space.sm)
            TaskMeta(task: task, showSubject: showSubject)
            IconButton(symbol: "ellipsis", help: "Task details", size: 24) { showEditor = true }
                .popover(isPresented: $showEditor, arrowEdge: .trailing) {
                    TaskEditor(task: task) { showEditor = false; confirmDelete = true }
                }
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit Details…") { showEditor = true }
            Button(task.isDone ? "Mark Incomplete" : "Mark Complete") { task.toggle() }
            Menu("Due") {
                Button("Today") { task.dueDate = Calendar.current.startOfDay(for: .now) }
                Button("Tomorrow") { task.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) }
                Button("Next Week") { task.dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now)) }
                Divider()
                Button("No Due Date") { task.dueDate = nil }
            }
            Menu("Priority") {
                ForEach(TaskPriority.allCases) { p in Button(p.title) { task.priority = p } }
            }
            Divider()
            Button("Delete Task…", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("Delete “\(task.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Task", role: .destructive) {
                context.delete(task)
                try? context.save()
            }
        } message: {
            Text("This can't be undone.")
        }
    }
}

struct TaskMeta: View {
    let task: TaskItem
    var showSubject = true

    var body: some View {
        HStack(spacing: Space.sm) {
            if task.priority != .none {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(PriorityStyle.color(task.priority))
                    .help("\(task.priority.title) priority")
            }
            if let due = task.dueDate {
                Text(Fmt.relativeDay(due))
                    .font(Typo.callout)
                    .foregroundStyle(task.isOverdue ? Theme.danger : (Calendar.current.isDateInToday(due) && !task.isDone ? Theme.warning : Theme.textSecondary))
            }
            if showSubject { SubjectChip(subject: task.subject) }
        }
    }
}

enum PriorityStyle {
    static func color(_ p: TaskPriority) -> Color {
        switch p {
        case .high: Theme.danger
        case .medium: Theme.warning
        case .low: Theme.textSecondary
        case .none: Theme.textTertiary
        }
    }
}

struct TaskEditor: View {
    @Bindable var task: TaskItem
    var onDelete: () -> Void
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]
    /// The due date is edited as a draft and written back when the popover closes.
    /// Writing it live moves the task between list groups (No date → Today → Upcoming),
    /// which rebuilds the row that anchors this popover and dismisses it mid-edit.
    @State private var draftDue: Date?

    init(task: TaskItem, onDelete: @escaping () -> Void) {
        self.task = task
        self.onDelete = onDelete
        _draftDue = State(initialValue: task.dueDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            TextField("Task", text: $task.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.title)
            TextField("Notes", text: $task.notes, axis: .vertical)
                .textFieldStyle(.os)
                .lineLimit(3...8)

            FieldRow(label: "Due date") {
                HStack {
                    Toggle("Has due date", isOn: Binding(
                        get: { draftDue != nil },
                        set: { draftDue = $0 ? (draftDue ?? Calendar.current.startOfDay(for: .now)) : nil }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    if draftDue != nil {
                        DatePicker("Due", selection: Binding(get: { draftDue ?? .now }, set: { draftDue = $0 }),
                                   displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                    }
                }
            }

            HStack(spacing: Space.lg) {
                FieldRow(label: "Priority") {
                    Picker("Priority", selection: Binding(get: { task.priority }, set: { task.priority = $0 })) {
                        ForEach(TaskPriority.allCases) { p in Text(p.title).tag(p) }
                    }
                    .labelsHidden()
                }
                FieldRow(label: "Subject") {
                    Picker("Subject", selection: Binding(get: { task.subject?.id }, set: { id in
                        task.subject = subjects.first { $0.id == id }
                    })) {
                        Text("None").tag(UUID?.none)
                        ForEach(subjects) { s in Text(s.name).tag(UUID?.some(s.id)) }
                    }
                    .labelsHidden()
                }
            }

            HStack {
                if let completed = task.completedAt {
                    Text("Completed \(completed.formatted(date: .abbreviated, time: .shortened))")
                        .font(Typo.callout).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Button("Delete", role: .destructive, action: onDelete).buttonStyle(.osDestructive)
            }
        }
        .padding(Space.xl)
        .frame(width: 340)
        .onDisappear(perform: commitDue)
    }

    private func commitDue() {
        guard !task.isDeleted, task.dueDate != draftDue else { return }
        task.dueDate = draftDue
    }
}

/// Inline "add a task" bar with optional subject/due/priority.
struct NewTaskBar: View {
    let subjects: [Subject]
    var defaultSubjectID: UUID?
    var lockedSubject: Subject? = nil
    let onCreate: (TaskItem) -> Void

    @State private var title = ""
    @State private var due: Date?
    @State private var priority: TaskPriority = .none
    @State private var subjectID: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textTertiary)
            TextField("Add a task and press Return", text: $title)
                .textFieldStyle(.plain)
                .font(Typo.body)
                .focused($focused)
                .onSubmit(create)
            Menu {
                Button("Today") { due = Calendar.current.startOfDay(for: .now) }
                Button("Tomorrow") { due = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) }
                Button("Next Week") { due = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now)) }
                Divider()
                Button("No Due Date") { due = nil }
            } label: {
                Label(due.map { Fmt.relativeDay($0) } ?? "Due", systemImage: "calendar")
            }
            .menuStyle(.button).buttonStyle(OSButtonStyle(variant: .ghost, compact: true)).fixedSize()
            Menu {
                ForEach(TaskPriority.allCases) { p in Button(p.title) { priority = p } }
            } label: {
                Label(priority == .none ? "Priority" : priority.title, systemImage: "flag")
            }
            .menuStyle(.button).buttonStyle(OSButtonStyle(variant: .ghost, compact: true)).fixedSize()
            if lockedSubject == nil && !subjects.isEmpty {
                Menu {
                    Button("No Subject") { subjectID = nil }
                    Divider()
                    ForEach(subjects) { s in Button(s.name) { subjectID = s.id } }
                } label: {
                    Label(subjects.first { $0.id == subjectID }?.name ?? "Subject", systemImage: "book.closed")
                }
                .menuStyle(.button).buttonStyle(OSButtonStyle(variant: .ghost, compact: true)).fixedSize()
            }
        }
        .padding(.horizontal, Space.md)
        .frame(height: 40)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(focused ? Theme.borderStrong : Theme.border))
        .onAppear { subjectID = defaultSubjectID }
        .onChange(of: defaultSubjectID) { _, new in subjectID = new }
    }

    private func create() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let subject = lockedSubject ?? subjects.first { $0.id == subjectID }
        let task = TaskItem(title: t, subject: subject, dueDate: due, priority: priority)
        onCreate(task)
        title = ""
        due = nil
        priority = .none
        focused = true
    }
}
