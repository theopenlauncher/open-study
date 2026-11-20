//
//  SidebarView.swift
//  open-study
//
//  Hybrid sidebar: global navigation, subjects with their topic pages,
//  settings (DESIGN.md §4).
//

import SwiftUI
import SwiftData
import PostHog

struct SidebarView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    @State private var editingSubject: Subject?
    @State private var subjectToDelete: Subject?
    @State private var renamingPage: UUID?
    @State private var pageToDelete: TopicPage?
    @State private var dropTarget: UUID?
    @State private var dropAtEnd = false

    var body: some View {
        @Bindable var router = router
        VStack(alignment: .leading, spacing: 0) {
            brand
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SidebarItem.global, id: \.self) { item in
                        GlobalNavRow(item: item, isActive: router.selection == item) {
                            router.selection = item
                        }
                    }

                    subjectsHeader
                        .padding(.top, Space.xl)
                        .padding(.bottom, Space.xs)

                    if subjects.isEmpty {
                        SidebarRow(symbol: "plus", title: "New subject", isActive: false, muted: true) {
                            router.showNewSubject = true
                        }
                    }

                    ForEach(subjects) { subject in
                        subjectRow(subject)
                        if router.expandedSubjects.contains(subject.id) {
                            ForEach(subject.sortedPages) { page in
                                pageRow(page, in: subject)
                            }
                        }
                    }

                    // End drop zone for reordering
                    Color.clear
                        .frame(height: 16)
                        .overlay(alignment: .top) {
                            if dropAtEnd { DropLine() }
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first.flatMap(UUID.init) else { return false }
                            moveSubject(id, before: nil)
                            return true
                        } isTargeted: { dropAtEnd = $0 }
                }
                .padding(.horizontal, Space.md)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)
            footer
        }
        .background(Theme.canvas)
        .popover(isPresented: $router.showNewSubject, arrowEdge: .trailing) {
            SubjectEditor(subject: nil) { name, symbol, color in
                createSubject(name: name, symbol: symbol, color: color)
                router.showNewSubject = false
            }
        }
        .confirmationDialog(
            "Delete “\(subjectToDelete?.name ?? "")”?",
            isPresented: Binding(get: { subjectToDelete != nil }, set: { if !$0 { subjectToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Subject", role: .destructive) {
                if let subjectToDelete { deleteSubject(subjectToDelete) }
            }
        } message: {
            Text("The subject's page, its topic pages and their blocks will be deleted. Tasks, flashcard decks, quizzes, documents and calendar events are kept and become unassigned.")
        }
        .confirmationDialog(
            "Delete “\(pageToDelete?.displayTitle ?? "")”?",
            isPresented: Binding(get: { pageToDelete != nil }, set: { if !$0 { pageToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Page", role: .destructive) {
                if let pageToDelete { TopicPages.delete(pageToDelete, context: context, router: router) }
                pageToDelete = nil
            }
        } message: {
            Text(TopicPages.deleteMessage)
        }
    }

    // MARK: Pieces

    private var brand: some View {
        HStack(spacing: 8) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("Open Study")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, Space.md + 10)
        .padding(.top, Space.md)
        .padding(.bottom, Space.xl)
    }

    private var subjectsHeader: some View {
        HStack {
            Text("SUBJECTS")
                .font(Typo.label)
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            IconButton(symbol: "plus", help: "New subject (⇧⌘N)", size: 22, onCanvas: true) {
                router.showNewSubject = true
            }
        }
        .padding(.leading, 10)
    }

    private func subjectRow(_ subject: Subject) -> some View {
        let id = subject.id
        let hasPages = !subject.pages.isEmpty
        let expanded = router.expandedSubjects.contains(id)
        return SidebarRow(
            symbol: subject.symbol,
            title: subject.name.isEmpty ? "Untitled" : subject.name,
            isActive: router.selection == .subject(id),
            tint: SubjectColor.from(subject.colorKey).color,
            disclosure: hasPages ? expanded : nil,
            onToggle: { toggleExpanded(id) },
            onAdd: { TopicPages.create(in: subject, context: context, router: router) },
            addHelp: "Add a page to \(subject.name)"
        ) {
            router.selection = .subject(id)
            if hasPages { router.expandedSubjects.insert(id) }
        }
        .overlay(alignment: .top) {
            if dropTarget == id { DropLine().offset(y: -1) }
        }
        .draggable(id.uuidString) {
            HStack(spacing: 8) {
                Image(systemName: subject.symbol).foregroundStyle(SubjectColor.from(subject.colorKey).color)
                Text(subject.name).font(Typo.nav)
            }
            .padding(8)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.control))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(UUID.init) else { return false }
            if let page = page(withID: dragged) {
                // Dropping a page on a subject moves it into that subject.
                TopicPages.move(page, to: subject, before: nil)
                router.expandedSubjects.insert(id)
            } else {
                moveSubject(dragged, before: id)
            }
            dropTarget = nil
            return true
        } isTargeted: { targeted in
            dropTarget = targeted ? id : (dropTarget == id ? nil : dropTarget)
        }
        .popover(isPresented: Binding(get: { editingSubject?.id == id }, set: { if !$0 { editingSubject = nil } }), arrowEdge: .trailing) {
            SubjectEditor(subject: subject) { name, symbol, color in
                subject.name = name
                subject.symbol = symbol
                subject.colorKey = color
                editingSubject = nil
            }
        }
        .contextMenu {
            Button("Open") { router.selection = .subject(id) }
            Button("New Page") { TopicPages.create(in: subject, context: context, router: router) }
            // Hover-free way to expand/collapse (the chevron only shows on hover).
            if hasPages {
                Button(expanded ? "Hide Pages" : "Show Pages") { toggleExpanded(id) }
            }
            Button("Edit Subject…") { editingSubject = subject }
            Divider()
            Button("Move Up") { shift(subject, by: -1) }
                .disabled(subjects.first?.id == id)
            Button("Move Down") { shift(subject, by: 1) }
                .disabled(subjects.last?.id == id)
            Divider()
            Button("Delete Subject…", role: .destructive) { subjectToDelete = subject }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 10).padding(.bottom, Space.sm)
            SidebarRow(symbol: SidebarItem.settings.symbol, title: "Settings", isActive: router.selection == .settings) {
                router.selection = .settings
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.bottom, Space.md)
    }

    private func pageRow(_ page: TopicPage, in subject: Subject) -> some View {
        let id = page.id
        let pages = subject.sortedPages
        return SidebarRow(
            symbol: page.symbol,
            title: page.displayTitle,
            isActive: router.selection == .page(id),
            muted: page.title.isEmpty,
            indent: 22,
            iconSize: 13
        ) {
            router.selection = .page(id)
        }
        .overlay(alignment: .top) {
            if dropTarget == id { DropLine().offset(y: -1).padding(.leading, 22) }
        }
        .draggable(id.uuidString) {
            HStack(spacing: 8) {
                Image(systemName: page.symbol)
                Text(page.displayTitle).font(Typo.nav)
            }
            .padding(8)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.control))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(UUID.init), let moving = self.page(withID: dragged) else { return false }
            TopicPages.move(moving, to: subject, before: page)
            dropTarget = nil
            return true
        } isTargeted: { targeted in
            dropTarget = targeted ? id : (dropTarget == id ? nil : dropTarget)
        }
        .popover(isPresented: Binding(get: { renamingPage == id }, set: { if !$0 { renamingPage = nil } }), arrowEdge: .trailing) {
            PageRenamer(page: page) { renamingPage = nil }
        }
        .contextMenu {
            Button("Open") { router.selection = .page(id) }
            Button("Rename…") { renamingPage = id }
            Divider()
            Button("Move Up") { TopicPages.shift(page, by: -1) }
                .disabled(pages.first?.id == id)
            Button("Move Down") { TopicPages.shift(page, by: 1) }
                .disabled(pages.last?.id == id)
            Divider()
            Button("Delete Page…", role: .destructive) { pageToDelete = page }
        }
    }

    private func page(withID id: UUID) -> TopicPage? {
        for subject in subjects {
            if let page = subject.pages.first(where: { $0.id == id }) { return page }
        }
        return nil
    }

    private func toggleExpanded(_ id: UUID) {
        withAnimation(Motion.fade) {
            if router.expandedSubjects.contains(id) { router.expandedSubjects.remove(id) }
            else { router.expandedSubjects.insert(id) }
        }
    }

    // MARK: Actions

    private func createSubject(name: String, symbol: String, color: String) {
        let subject = Subject(name: name, symbol: symbol, colorKey: color, sortIndex: (subjects.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(subject)
        do {
            try context.save()
            PostHogSDK.shared.capture("subject_created")
        } catch {}
        router.selection = .subject(subject.id)
    }

    private func deleteSubject(_ subject: Subject) {
        // Leave the subject's page or any of its topic pages before deleting them.
        let showingThisSubject = router.selection == .subject(subject.id)
            || subject.pages.contains { router.selection == .page($0.id) }
        if showingThisSubject { router.selection = .home }
        router.expandedSubjects.remove(subject.id)
        context.delete(subject)
        try? context.save()
        subjectToDelete = nil
    }

    private func moveSubject(_ id: UUID, before target: UUID?) {
        var ordered = subjects
        guard let from = ordered.firstIndex(where: { $0.id == id }) else { return }
        let moving = ordered.remove(at: from)
        let to = target.flatMap { t in ordered.firstIndex(where: { $0.id == t }) } ?? ordered.count
        ordered.insert(moving, at: to)
        withAnimation(Motion.fade) {
            for (i, s) in ordered.enumerated() { s.sortIndex = i }
        }
        dropTarget = nil
        dropAtEnd = false
    }

    private func shift(_ subject: Subject, by delta: Int) {
        var ordered = subjects
        guard let i = ordered.firstIndex(where: { $0.id == subject.id }) else { return }
        let j = i + delta
        guard ordered.indices.contains(j) else { return }
        ordered.swapAt(i, j)
        withAnimation(Motion.fade) {
            for (k, s) in ordered.enumerated() { s.sortIndex = k }
        }
    }
}

struct DropLine: View {
    var body: some View {
        Capsule().fill(Theme.accent).frame(height: 2)
    }
}

struct SidebarRow: View {
    let symbol: String
    let title: String
    let isActive: Bool
    var badge: String? = nil
    var tint: Color? = nil
    var muted = false
    var indent: CGFloat = 0
    var iconSize: CGFloat = 15
    /// nil hides the disclosure chevron; otherwise whether the row is expanded.
    var disclosure: Bool? = nil
    var onToggle: (() -> Void)? = nil
    /// Shows a hover "+" on the trailing edge.
    var onAdd: (() -> Void)? = nil
    var addHelp = "Add"
    let action: () -> Void
    @State private var hovering = false

    private var showChevron: Bool { hovering && disclosure != nil }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: iconSize))
                    .foregroundStyle(tint ?? (isActive ? Theme.textPrimary : Theme.textSecondary))
                    .frame(width: 20)
                    .opacity(showChevron ? 0 : 1)
                Text(title)
                    .font(isActive ? Typo.nav.weight(.medium) : Typo.nav)
                    .foregroundStyle(muted ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge { Badge(text: badge) }
                if onAdd != nil { Color.clear.frame(width: 20) }
            }
            .padding(.leading, 10 + indent)
            .padding(.trailing, 10)
            .frame(height: 32)
            .background(
                isActive ? Theme.sidebarActive : (hovering ? Theme.sidebarHover : .clear),
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            if showChevron, let disclosure, let onToggle {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(disclosure ? 90 : 0))
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                        .hoverHighlight(cornerRadius: 5, onCanvas: true)
                }
                .buttonStyle(.plain)
                .padding(.leading, 10 + indent)
                .help(disclosure ? "Hide pages" : "Show pages")
                .accessibilityLabel(disclosure ? "Hide pages" : "Show pages")
            }
        }
        .overlay(alignment: .trailing) {
            if hovering, let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                        .hoverHighlight(cornerRadius: 5, onCanvas: true)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .help(addHelp)
                .accessibilityLabel(addHelp)
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Subject editor

struct SubjectEditor: View {
    let subject: Subject?
    let onSave: (String, String, String) -> Void

    @State private var name = ""
    @State private var symbol = "book.closed"
    @State private var color = SubjectColor.slate.rawValue
    @FocusState private var nameFocused: Bool

    static let symbols = [
        "book.closed", "function", "atom", "flask", "leaf", "globe.europe.africa", "building.columns",
        "character.book.closed", "music.note", "paintpalette", "cpu", "chart.line.uptrend.xyaxis",
        "brain.head.profile", "heart.text.square", "scalemass", "hammer", "theatermasks", "pencil.and.ruler",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(subject == nil ? "New subject" : "Edit subject").font(Typo.title)
            TextField("Subject name, e.g. Physics", text: $name)
                .textFieldStyle(.os)
                .focused($nameFocused)
                .onSubmit(save)

            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("Icon")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 6), spacing: 6) {
                    ForEach(Self.symbols, id: \.self) { s in
                        Button { symbol = s } label: {
                            Image(systemName: s)
                                .font(.system(size: 14))
                                .foregroundStyle(s == symbol ? SubjectColor.from(color).color : Theme.textSecondary)
                                .frame(width: 30, height: 30)
                                .background(s == symbol ? Theme.muted : .clear, in: RoundedRectangle(cornerRadius: Radius.icon))
                                .overlay(RoundedRectangle(cornerRadius: Radius.icon).strokeBorder(s == symbol ? Theme.borderStrong : .clear))
                        }
                        .buttonStyle(.plain)
                        .help(s)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                SectionLabel("Colour")
                HStack(spacing: 8) {
                    ForEach(SubjectColor.allCases) { c in
                        Button { color = c.rawValue } label: {
                            Circle().fill(c.color).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Theme.raised, lineWidth: 2).padding(-0.5))
                                .overlay(Circle().strokeBorder(c.rawValue == color ? Theme.ink : .clear, lineWidth: 1.5).padding(-3))
                        }
                        .buttonStyle(.plain)
                        .help(c.name)
                        .accessibilityLabel(c.name)
                    }
                }
                .padding(.leading, 3)
            }

            HStack {
                Spacer()
                Button(subject == nil ? "Create subject" : "Save", action: save)
                    .buttonStyle(.osPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.xl)
        .frame(width: 280)
        .onAppear {
            if let subject {
                name = subject.name
                symbol = subject.symbol
                color = subject.colorKey
            } else {
                color = SubjectColor.allCases.randomElement()?.rawValue ?? "slate"
            }
            nameFocused = true
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, symbol, color)
    }
}

// MARK: - Global nav rows

/// Global nav rows. The Flashcards and Tasks badges live in their own views
/// with narrow queries, so card reviews and task edits only redraw the badge
/// row instead of the whole sidebar. TimelineView refreshes the cut-off.
private struct GlobalNavRow: View {
    let item: SidebarItem
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        switch item {
        case .flashcards:
            // `ctx.date` is the start of the minute; use the real time so cards
            // created earlier in this minute already count as due.
            TimelineView(.everyMinute) { _ in
                DueCardsNavRow(item: item, now: Date(), isActive: isActive, action: action)
            }
        case .tasks:
            TimelineView(.everyMinute) { ctx in
                DueTasksNavRow(item: item, now: ctx.date, isActive: isActive, action: action)
            }
        default:
            SidebarRow(symbol: item.symbol, title: item.title, isActive: isActive, action: action)
        }
    }
}

private struct DueCardsNavRow: View {
    let item: SidebarItem
    let isActive: Bool
    let action: () -> Void
    @Query private var due: [Flashcard]

    init(item: SidebarItem, now: Date, isActive: Bool, action: @escaping () -> Void) {
        self.item = item
        self.isActive = isActive
        self.action = action
        _due = Query(filter: #Predicate<Flashcard> { $0.dueDate <= now })
    }

    var body: some View {
        SidebarRow(symbol: item.symbol, title: item.title, isActive: isActive,
                   badge: due.isEmpty ? nil : "\(due.count)", action: action)
    }
}

private struct DueTasksNavRow: View {
    let item: SidebarItem
    let isActive: Bool
    let action: () -> Void
    @Query private var due: [TaskItem]

    init(item: SidebarItem, now: Date, isActive: Bool, action: @escaping () -> Void) {
        self.item = item
        self.isActive = isActive
        self.action = action
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let never = Date.distantFuture
        _due = Query(filter: #Predicate<TaskItem> { !$0.isDone && ($0.dueDate ?? never) < endOfToday })
    }

    var body: some View {
        SidebarRow(symbol: item.symbol, title: item.title, isActive: isActive,
                   badge: due.isEmpty ? nil : "\(due.count)", action: action)
    }
}

// MARK: - Page renamer

private struct PageRenamer: View {
    @Bindable var page: TopicPage
    let onDone: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Rename page").font(Typo.title)
            TextField("Page name, e.g. Thermodynamics", text: $page.title)
                .textFieldStyle(.os)
                .focused($focused)
                .onSubmit(onDone)
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.osPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 280)
        .onAppear { focused = true }
    }
}
