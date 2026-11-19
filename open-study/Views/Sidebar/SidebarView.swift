//
//  SidebarView.swift
//  open-study
//
//  Hybrid sidebar: global navigation, subjects, settings (DESIGN.md §4).
//

import SwiftUI
import SwiftData
import PostHog

struct SidebarView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]
    @Query private var cards: [Flashcard]
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }) private var openTasks: [TaskItem]

    @State private var editingSubject: Subject?
    @State private var subjectToDelete: Subject?
    @State private var dropTarget: UUID?
    @State private var dropAtEnd = false

    private var dueCardCount: Int {
        let now = Date()
        return cards.filter { $0.dueDate <= now }.count
    }

    private var dueTaskCount: Int {
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        return openTasks.filter { ($0.dueDate ?? .distantFuture) < endOfToday }.count
    }

    var body: some View {
        @Bindable var router = router
        VStack(alignment: .leading, spacing: 0) {
            brand
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(SidebarItem.global, id: \.self) { item in
                        SidebarRow(symbol: item.symbol, title: item.title, isActive: router.selection == item,
                                   badge: badge(for: item)) {
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
            Text("The subject's page and its blocks will be deleted. Tasks, flashcard decks, quizzes, documents and calendar events are kept and become unassigned.")
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
        return SidebarRow(
            symbol: subject.symbol,
            title: subject.name.isEmpty ? "Untitled" : subject.name,
            isActive: router.selection == .subject(id),
            tint: SubjectColor.from(subject.colorKey).color
        ) {
            router.selection = .subject(id)
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
            moveSubject(dragged, before: id)
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

    private func badge(for item: SidebarItem) -> String? {
        switch item {
        case .flashcards: dueCardCount > 0 ? "\(dueCardCount)" : nil
        case .tasks: dueTaskCount > 0 ? "\(dueTaskCount)" : nil
        default: nil
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
        if router.selection == .subject(subject.id) { router.selection = .home }
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
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(tint ?? (isActive ? Theme.textPrimary : Theme.textSecondary))
                    .frame(width: 20)
                Text(title)
                    .font(isActive ? Typo.nav.weight(.medium) : Typo.nav)
                    .foregroundStyle(muted ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge { Badge(text: badge) }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                isActive ? Theme.sidebarActive : (hovering ? Theme.sidebarHover : .clear),
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
