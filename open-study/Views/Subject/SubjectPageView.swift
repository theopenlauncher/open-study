//
//  SubjectPageView.swift
//  open-study
//
//  A subject's Notion-style page: an editable title, its topic pages, then a
//  column of user-built blocks. New subjects start completely blank.
//  `BlockCanvas` holds the block editing shared with topic pages.
//

import SwiftUI
import SwiftData

struct SubjectPageLoader: View {
    let subjectID: UUID
    @Query private var subjects: [Subject]

    init(subjectID: UUID) {
        self.subjectID = subjectID
        _subjects = Query(filter: #Predicate<Subject> { $0.id == subjectID })
    }

    var body: some View {
        if let subject = subjects.first {
            SubjectPageView(subject: subject)
        } else {
            EmptyStateView(symbol: "questionmark.folder", title: "Subject not found",
                           message: "This subject may have been deleted.")
                .frame(maxHeight: .infinity)
        }
    }
}

/// Closures the block chrome uses to mutate the page.
struct BlockPageActions {
    var insert: (BlockKind, Block?) -> Void
    var move: (UUID, UUID?) -> Void
    var shift: (Block, Int) -> Void
    var duplicate: (Block) -> Void
    var requestDelete: (Block) -> Void
}

/// What a block canvas edits: the subject's own page or one of its topic pages.
enum BlockOwner {
    case subject(Subject)
    case page(TopicPage)

    var sortedBlocks: [Block] {
        switch self {
        case .subject(let s): s.sortedBlocks
        case .page(let p): p.sortedBlocks
        }
    }

    /// Links a new block to its page. Topic-page blocks also point at the
    /// subject so subject-scoped widgets keep working.
    func attach(_ block: Block) {
        switch self {
        case .subject(let s): block.subject = s
        case .page(let p):
            block.page = p
            block.subject = p.subject
        }
    }
}

struct SubjectPageView: View {
    let subject: Subject
    var body: some View {
        BlockCanvas(owner: .subject(subject),
                    emptyHint: "This page is empty. Press / or click + to add your first block — notes, flashcards, tasks, a PDF and more. Use pages above to split the subject into topics.") {
            SubjectPageHeader(subject: subject)
        }
    }
}

/// Kept in its own view so typing in the title doesn't re-render every block.
private struct SubjectPageHeader: View {
    @Bindable var subject: Subject

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Image(systemName: subject.symbol)
                .font(.system(size: 30))
                .foregroundStyle(SubjectColor.from(subject.colorKey).color)
                .frame(height: 36)
            TextField("Untitled subject", text: $subject.name, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 36, weight: .regular, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            SubjectTopicList(subject: subject)
                .padding(.top, Space.sm)
        }
    }
}

/// The subject's topic pages, shown under its title.
private struct SubjectTopicList: View {
    let subject: Subject
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    var body: some View {
        let pages = subject.sortedPages
        VStack(alignment: .leading, spacing: 2) {
            if !pages.isEmpty {
                SectionLabel("Pages").padding(.bottom, Space.xs)
                ForEach(pages) { page in
                    Button { router.selection = .page(page.id) } label: {
                        HStack(spacing: Space.sm) {
                            Image(systemName: page.symbol)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 18)
                            Text(page.displayTitle)
                                .font(Typo.reading)
                                .foregroundStyle(page.title.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                                .underline(color: Theme.border)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                        .hoverHighlight(cornerRadius: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, -6)
                }
            }
            Button { TopicPages.create(in: subject, context: context, router: router) } label: {
                HStack(spacing: Space.sm) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium)).frame(width: 18)
                    Text(pages.isEmpty ? "Add a page for a topic" : "New page").font(Typo.body)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 6)
                .frame(height: 28)
                .contentShape(Rectangle())
                .hoverHighlight(cornerRadius: 6)
            }
            .buttonStyle(.plain)
            .padding(.leading, -6)
            .help("Create a page inside this subject")
        }
        .frame(maxWidth: 420, alignment: .leading)
    }
}

/// A Notion-style column of user-built blocks under a header. Used by the
/// subject page and topic pages.
struct BlockCanvas<Header: View>: View {
    let owner: BlockOwner
    let emptyHint: String
    @ViewBuilder let header: () -> Header
    @Environment(\.modelContext) private var context

    @State private var formatter = NoteFormatter()
    @State private var columnWidth: CGFloat = 780
    @State private var focusBlockID: UUID?
    @State private var inserterAnchor: UUID?
    @State private var showEndInserter = false
    @State private var trailingText = ""
    @State private var blockToDelete: Block?
    @State private var endDropTargeted = false
    @FocusState private var trailingFocused: Bool

    private var blocks: [Block] { owner.sortedBlocks }

    var body: some View {
        // Sort once per render; the layout helpers below reuse it.
        let ordered = blocks
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header()
                        .padding(.bottom, ordered.isEmpty ? Space.lg : Space.x3)

                    if ordered.isEmpty {
                        Text(emptyHint)
                            .font(Typo.body)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, Space.lg)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rows(ordered), id: \.first!.id) { row in
                            HStack(alignment: .top, spacing: Space.lg) {
                                ForEach(row) { block in
                                    BlockContainer(block: block, columnWidth: columnWidth, inserterAnchor: $inserterAnchor,
                                                   actions: actions) {
                                        BlockContent(block: block, formatter: formatter, focusBlockID: $focusBlockID,
                                                     onSlash: { inserterAnchor = block.id })
                                    }
                                    .frame(width: width(of: block, in: row))
                                }
                                if rowFraction(row) < 0.999 { Spacer(minLength: 0) }
                            }
                            .padding(.vertical, row.contains { !$0.kind.isInline } ? Space.sm : 0)
                        }
                    }

                    trailingInput
                        .padding(.top, ordered.isEmpty ? 0 : Space.md)
                }
                .frame(maxWidth: Layout.readingWidth, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { columnWidth = $0 }
                .padding(.leading, Layout.blockGutter + Space.md)
                .padding(.trailing, Space.x5)
                .padding(.top, Space.x4)
                .padding(.bottom, 140)
                .frame(maxWidth: .infinity)
            }

            if formatter.isEditing {
                NoteFormatBar(formatter: formatter)
                    .padding(.bottom, Space.xl)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.fade, value: formatter.isEditing)
        .confirmationDialog("Delete this \(blockToDelete?.kind.title.lowercased() ?? "block")?",
                            isPresented: Binding(get: { blockToDelete != nil }, set: { if !$0 { blockToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Block", role: .destructive) {
                if let blockToDelete { delete(blockToDelete) }
            }
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: Trailing input (Notion-style "type / for blocks")

    private var trailingInput: some View {
        HStack(spacing: 6) {
            Button { showEndInserter = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 22, height: 22)
                    .hoverHighlight(cornerRadius: 5)
            }
            .buttonStyle(.plain)
            .help("Add a block")
            .popover(isPresented: $showEndInserter, arrowEdge: .bottom) {
                BlockInserter { kind in
                    showEndInserter = false
                    insert(kind, after: blocks.last)
                }
            }
            .padding(.leading, -28)

            TextField("Type / for blocks, or just start writing", text: $trailingText)
                .textFieldStyle(.plain)
                .font(Typo.reading)
                .foregroundStyle(Theme.textPrimary)
                .focused($trailingFocused)
                .onChange(of: trailingText) { _, new in
                    if new == "/" {
                        trailingText = ""
                        showEndInserter = true
                    }
                }
                .onSubmit {
                    let text = trailingText.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    let block = makeBlock(.text, after: blocks.last)
                    block.text = text
                    block.richData = NoteCodec.make(plain: text)
                    trailingText = ""
                    trailingFocused = true
                }
        }
        .frame(minHeight: 32)
        .overlay(alignment: .top) {
            if endDropTargeted { DropLine() }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init) else { return false }
            move(id, before: nil)
            return true
        } isTargeted: { endDropTargeted = $0 }
    }

    // MARK: Layout

    /// Packs blocks into rows while their width fractions sum to ≤ 1.
    private func rows(_ blocks: [Block]) -> [[Block]] {
        var result: [[Block]] = []
        var current: [Block] = []
        var sum = 0.0
        for block in blocks {
            let w = block.kind.supportsWidth ? block.widthFraction : 1
            if !current.isEmpty && sum + w > 1.001 {
                result.append(current)
                current = []
                sum = 0
            }
            current.append(block)
            sum += w
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func rowFraction(_ row: [Block]) -> Double {
        row.reduce(0) { $0 + ($1.kind.supportsWidth ? $1.widthFraction : 1) }
    }

    private func width(of block: Block, in row: [Block]) -> CGFloat {
        let f = block.kind.supportsWidth ? block.widthFraction : 1
        return max(120, f * columnWidth - Space.lg * (1 - f))
    }

    // MARK: Mutations

    private var actions: BlockPageActions {
        BlockPageActions(
            insert: { kind, after in insert(kind, after: after) },
            move: { id, before in move(id, before: before) },
            shift: { block, delta in shift(block, by: delta) },
            duplicate: { duplicate($0) },
            requestDelete: { block in
                if isEmpty(block) { delete(block) } else { blockToDelete = block }
            }
        )
    }

    @discardableResult
    private func makeBlock(_ kind: BlockKind, after: Block?) -> Block {
        var ordered = blocks
        let block = Block(kind: kind, sortIndex: 0)
        context.insert(block)
        owner.attach(block)
        let index = after.flatMap { a in ordered.firstIndex(where: { $0.id == a.id }) }.map { $0 + 1 } ?? ordered.count
        // Match the width of the block we insert after so side-by-side layouts stay intact.
        if let after, kind.supportsWidth, after.kind.supportsWidth, after.widthFraction < 1 {
            block.widthFraction = after.widthFraction
        }
        ordered.insert(block, at: index)
        for (i, b) in ordered.enumerated() { b.sortIndex = i }
        try? context.save()
        return block
    }

    private func insert(_ kind: BlockKind, after: Block?) {
        inserterAnchor = nil
        withAnimation(Motion.fade) {
            let block = makeBlock(kind, after: after)
            if kind == .text { focusBlockID = block.id }
        }
    }

    private func move(_ id: UUID, before target: UUID?) {
        guard id != target else { return }
        var ordered = blocks
        guard let from = ordered.firstIndex(where: { $0.id == id }) else { return }
        let moving = ordered.remove(at: from)
        let to = target.flatMap { t in ordered.firstIndex(where: { $0.id == t }) } ?? ordered.count
        ordered.insert(moving, at: to)
        withAnimation(Motion.fade) {
            for (i, b) in ordered.enumerated() { b.sortIndex = i }
        }
    }

    private func shift(_ block: Block, by delta: Int) {
        var ordered = blocks
        guard let i = ordered.firstIndex(where: { $0.id == block.id }) else { return }
        let j = i + delta
        guard ordered.indices.contains(j) else { return }
        ordered.swapAt(i, j)
        withAnimation(Motion.fade) {
            for (k, b) in ordered.enumerated() { b.sortIndex = k }
        }
    }

    private func duplicate(_ block: Block) {
        let copy = makeBlock(block.kind, after: block)
        copy.title = block.title
        copy.text = block.text
        copy.richData = block.richData
        copy.level = block.level
        copy.symbol = block.symbol
        copy.toneRaw = block.toneRaw
        copy.itemsData = block.itemsData
        copy.widthFraction = block.widthFraction
        copy.height = block.height
        copy.deck = block.deck
        copy.document = block.document
        copy.quiz = block.quiz
    }

    private func isEmpty(_ block: Block) -> Bool {
        switch block.kind {
        case .text, .heading, .callout: block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .divider, .pomodoro, .statistics: true
        case .checklist: block.checklist.isEmpty && block.title.isEmpty
        case .tasks: block.tasks.isEmpty
        case .flashcards: block.deck == nil
        case .pdf: block.document == nil
        case .quiz: block.quiz == nil
        }
    }

    private var deleteMessage: String {
        guard let block = blockToDelete else { return "" }
        switch block.kind {
        case .tasks: return "The tasks in this list are kept and stay visible in Tasks."
        case .flashcards: return "Only the block is removed. The deck and its cards stay in Flashcards."
        case .pdf: return "Only the block is removed. The PDF and its annotations are kept and can be added again."
        case .quiz: return "Only the block is removed. The quiz is kept in Flashcards › Quizzes."
        default: return "This can't be undone."
        }
    }

    private func delete(_ block: Block) {
        withAnimation(Motion.fade) {
            context.delete(block)
            for (i, b) in blocks.filter({ $0.id != block.id }).enumerated() { b.sortIndex = i }
        }
        try? context.save()
        blockToDelete = nil
    }
}
