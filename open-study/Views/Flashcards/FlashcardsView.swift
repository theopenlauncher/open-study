//
//  FlashcardsView.swift
//  open-study
//
//  Decks, cards, spaced-repetition review and quizzes.
//

import SwiftUI
import SwiftData
import PostHog

struct ReviewSession: Identifiable {
    let id = UUID()
    let title: String
    let cards: [Flashcard]
}

struct FlashcardsView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @Query private var cards: [Flashcard]
    @Query private var reviews: [ReviewLog]

    @AppStorage("flashcards.mode") private var mode = "decks"
    @State private var selectedDeckID: UUID?
    @State private var review: ReviewSession?
    @State private var showNewDeck = false
    @State private var showImport = false

    private var dueCards: [Flashcard] {
        let now = Date()
        return cards.filter { $0.dueDate <= now }.sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        Group {
            if mode == "decks", let id = selectedDeckID, let deck = decks.first(where: { $0.id == id }) {
                DeckDetailView(deck: deck, onBack: { withAnimation(Motion.fade) { selectedDeckID = nil } }, onReview: { review = $0 })
            } else {
                overview
            }
        }
        .sheet(item: $review) { session in
            ReviewView(session: session)
        }
        .sheet(isPresented: $showImport) {
            ImportCardsView(preselectedDeck: nil)
        }
        .onAppear(perform: consumePendingDeck)
        .onChange(of: router.pendingDeckID) { consumePendingDeck() }
    }

    private func consumePendingDeck() {
        if let id = router.pendingDeckID {
            mode = "decks"
            selectedDeckID = id
            router.pendingDeckID = nil
        }
    }

    private var overview: some View {
        PageScroll {
            PageHeader(title: mode == "decks" ? "Flashcards" : "Quizzes", subtitle: subtitle) {
                OSSegmented(options: [("decks", "Flashcards"), ("quizzes", "Quizzes")], selection: $mode)
            }
            .padding(.bottom, Space.xxl)

            if mode == "decks" { decksContent } else { QuizzesListView() }
        }
    }

    private var subtitle: String {
        if mode == "quizzes" { return "Practice tests you write yourself." }
        if cards.isEmpty { return "Remember more with spaced repetition." }
        let reviewedToday = reviews.filter { Calendar.current.isDateInToday($0.date) }.count
        return "\(dueCards.count) due · \(reviewedToday) reviewed today"
    }

    @ViewBuilder private var decksContent: some View {
        HStack(spacing: Space.sm) {
            Button {
                review = ReviewSession(title: "All decks", cards: dueCards)
            } label: {
                Label(dueCards.isEmpty ? "Nothing due" : "Review \(dueCards.count) due", systemImage: "play.fill")
            }
            .buttonStyle(.osPrimary)
            .disabled(dueCards.isEmpty)
            .keyboardShortcut("r", modifiers: .command)

            Button { showNewDeck = true } label: { Label("New deck", systemImage: "plus") }
                .buttonStyle(.osSecondary)
                .popover(isPresented: $showNewDeck, arrowEdge: .bottom) {
                    NewDeckForm { deck in
                        context.insert(deck)
                        do {
                            try context.save()
                            PostHogSDK.shared.capture("deck_created", properties: ["has_subject": deck.subject != nil])
                        } catch {}
                        showNewDeck = false
                        selectedDeckID = deck.id
                    }
                }
            Button { showImport = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                .buttonStyle(.osSecondary)
            Spacer()
        }
        .padding(.bottom, Space.xxl)

        if decks.isEmpty {
            OSCard {
                EmptyStateView(
                    symbol: "rectangle.on.rectangle.angled",
                    title: "Create your first deck",
                    message: "A deck is a set of cards with a question on the front and the answer on the back. Open Study schedules each card so you review it just before you'd forget.",
                    actionTitle: "New deck", actionSymbol: "plus"
                ) { showNewDeck = true }
            }
        } else {
            SectionLabel("Decks").padding(.bottom, Space.md)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Space.lg)], spacing: Space.lg) {
                ForEach(decks) { deck in
                    DeckCard(deck: deck, reviews: reviews) {
                        withAnimation(Motion.fade) { selectedDeckID = deck.id }
                    } onReview: {
                        review = ReviewSession(title: deck.name, cards: deck.dueCards)
                    }
                }
            }
        }
    }
}

struct DeckCard: View {
    let deck: Deck
    let reviews: [ReviewLog]
    let onOpen: () -> Void
    let onReview: () -> Void
    @State private var hovering = false

    var body: some View {
        let due = deck.dueCards.count
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top) {
                Text(deck.name.isEmpty ? "Untitled deck" : deck.name)
                    .font(Typo.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Spacer()
                SubjectChip(subject: deck.subject)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(deck.cards.count)").font(Typo.numeralSmall)
                Text(deck.cards.count == 1 ? "card" : "cards").font(Typo.body).foregroundStyle(Theme.textSecondary)
                Spacer()
                if due > 0 {
                    Text("\(due) due").font(Typo.callout.weight(.medium)).foregroundStyle(Theme.warning)
                } else if !deck.cards.isEmpty {
                    Text("Up to date").font(Typo.callout).foregroundStyle(Theme.textTertiary)
                }
            }
            HStack {
                Button("Open", action: onOpen).buttonStyle(OSButtonStyle(variant: .ghost, compact: true))
                Spacer()
                Button("Review", action: onReview)
                    .buttonStyle(OSButtonStyle(variant: .secondary, compact: true))
                    .disabled(due == 0)
            }
        }
        .padding(Space.lg)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(hovering ? Theme.borderStrong : Theme.border))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

struct NewDeckForm: View {
    var subject: Subject? = nil
    let onCreate: (Deck) -> Void
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]
    @State private var name = ""
    @State private var subjectID: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("New deck").font(Typo.title)
            TextField("Deck name, e.g. Organic reactions", text: $name)
                .textFieldStyle(.os)
                .focused($focused)
                .onSubmit(create)
            if subject == nil {
                Picker("Subject", selection: $subjectID) {
                    Text("No subject").tag(UUID?.none)
                    ForEach(subjects) { s in Text(s.name).tag(UUID?.some(s.id)) }
                }
            }
            HStack {
                Spacer()
                Button("Create deck", action: create)
                    .buttonStyle(.osPrimary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Space.xl)
        .frame(width: 300)
        .onAppear { focused = true; subjectID = subject?.id }
    }

    private func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        onCreate(Deck(name: n, subject: subject ?? subjects.first { $0.id == subjectID }))
    }
}

// MARK: - Deck detail

struct DeckDetailView: View {
    @Bindable var deck: Deck
    let onBack: () -> Void
    let onReview: (ReviewSession) -> Void
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    @State private var search = ""
    @State private var tagFilter: String?
    @State private var editingCard: Flashcard?
    @State private var addingCard = false
    @State private var showImport = false
    @State private var confirmDeleteDeck = false
    @State private var cardToDelete: Flashcard?

    private var allTags: [String] { Array(Set(deck.cards.flatMap(\.tags))).sorted() }

    private var visibleCards: [Flashcard] {
        let q = search.lowercased()
        return deck.cards
            .filter { q.isEmpty || $0.front.lowercased().contains(q) || $0.back.lowercased().contains(q) }
            .filter { tagFilter == nil || $0.tags.contains(tagFilter!) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var accuracy: Double? {
        let logs = deck.cards.flatMap(\.reviews)
        guard !logs.isEmpty else { return nil }
        return Double(logs.filter { $0.rating.isCorrect }.count) / Double(logs.count)
    }

    var body: some View {
        PageScroll {
            Button(action: onBack) {
                Label("Flashcards", systemImage: "chevron.left").font(Typo.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .padding(.bottom, Space.md)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Deck name", text: $deck.name)
                        .textFieldStyle(.plain)
                        .font(Typo.display)
                    Picker("Subject", selection: Binding(get: { deck.subject?.id }, set: { id in deck.subject = subjects.first { $0.id == id } })) {
                        Text("No subject").tag(UUID?.none)
                        ForEach(subjects) { s in Text(s.name).tag(UUID?.some(s.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                Menu {
                    Button("Import Cards…") { showImport = true }
                    Divider()
                    Button("Delete Deck…", role: .destructive) { confirmDeleteDeck = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(OSButtonStyle(variant: .ghost))
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.bottom, Space.xxl)

            HStack(spacing: Space.md) {
                StatTile(value: "\(deck.cards.count)", unit: "cards")
                StatTile(value: "\(deck.dueCards.count)", unit: "due now")
                StatTile(value: "\(deck.cards.filter(\.isNew).count)", unit: "new")
                StatTile(value: accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", unit: "accuracy")
            }
            .padding(.bottom, Space.xxl)

            HStack(spacing: Space.sm) {
                Button {
                    onReview(ReviewSession(title: deck.name, cards: deck.dueCards))
                } label: { Label(deck.dueCards.isEmpty ? "Nothing due" : "Review \(deck.dueCards.count)", systemImage: "play.fill") }
                    .buttonStyle(.osPrimary)
                    .disabled(deck.dueCards.isEmpty)
                Button {
                    onReview(ReviewSession(title: "\(deck.name) · cram", cards: deck.cards.shuffled()))
                } label: { Label("Practice all", systemImage: "shuffle") }
                    .buttonStyle(.osSecondary)
                    .disabled(deck.cards.isEmpty)
                    .help("Review every card now. Ratings still update the schedule.")
                Button { addingCard = true } label: { Label("Add card", systemImage: "plus") }
                    .buttonStyle(.osSecondary)
                    .keyboardShortcut("n", modifiers: .command)
                Spacer()
                if !allTags.isEmpty {
                    GhostMenu(title: tagFilter.map { "#\($0)" } ?? "All tags", symbol: "tag") {
                        Button("All tags") { tagFilter = nil }
                        Divider()
                        ForEach(allTags, id: \.self) { t in Button("#\(t)") { tagFilter = t } }
                    }
                }
                TextField("Search cards", text: $search)
                    .textFieldStyle(.os)
                    .frame(width: 200)
            }
            .padding(.bottom, Space.lg)

            if deck.cards.isEmpty {
                OSCard {
                    EmptyStateView(symbol: "plus.rectangle.on.rectangle", title: "No cards yet",
                                   message: "Add cards one at a time, or import a list from a spreadsheet or text file.",
                                   actionTitle: "Add card", actionSymbol: "plus") { addingCard = true }
                }
            } else if visibleCards.isEmpty {
                Text("No cards match your search.").font(Typo.body).foregroundStyle(Theme.textTertiary).padding(Space.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleCards.enumerated()), id: \.element.id) { i, card in
                        if i > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                        CardRow(card: card) { editingCard = card } onDelete: { cardToDelete = card }
                    }
                }
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
            }
        }
        .sheet(isPresented: $addingCard) { CardEditor(deck: deck, card: nil) }
        .sheet(item: $editingCard) { card in CardEditor(deck: deck, card: card) }
        .sheet(isPresented: $showImport) { ImportCardsView(preselectedDeck: deck) }
        .confirmationDialog("Delete “\(deck.name)”?", isPresented: $confirmDeleteDeck, titleVisibility: .visible) {
            Button("Delete Deck and \(deck.cards.count) Cards", role: .destructive) {
                onBack()
                context.delete(deck)
                try? context.save()
            }
        } message: {
            Text("All cards in this deck will be deleted. Your past review statistics are kept.")
        }
        .confirmationDialog("Delete this card?", isPresented: Binding(get: { cardToDelete != nil }, set: { if !$0 { cardToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Card", role: .destructive) {
                if let cardToDelete { context.delete(cardToDelete) }
                try? context.save()
                cardToDelete = nil
            }
        }
    }
}

struct CardRow: View {
    let card: Flashcard
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            Text(card.front).font(Typo.body).foregroundStyle(Theme.textPrimary)
                .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            Text(card.back).font(Typo.body).foregroundStyle(Theme.textSecondary)
                .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Text(card.isNew ? "New" : (card.dueDate <= .now ? "Due" : Fmt.relativeDay(card.dueDate)))
                    .font(Typo.callout)
                    .foregroundStyle(card.dueDate <= .now && !card.isNew ? Theme.warning : Theme.textTertiary)
                if !card.tags.isEmpty {
                    Text(card.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(Typo.callout).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }
            .frame(width: 120, alignment: .trailing)
            HStack(spacing: 0) {
                IconButton(symbol: "pencil", help: "Edit card", size: 24, action: onEdit)
                IconButton(symbol: "trash", help: "Delete card", size: 24, action: onDelete)
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(hovering ? Theme.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit Card…", action: onEdit)
            Button("Delete Card…", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Card editor

struct CardEditor: View {
    let deck: Deck
    let card: Flashcard?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var front = ""
    @State private var back = ""
    @State private var tags = ""
    @State private var addedCount = 0
    @FocusState private var frontFocused: Bool

    var body: some View {
        SheetScaffold(title: card == nil ? "Add card" : "Edit card",
                      subtitle: card == nil ? "Adding to \(deck.name). Press ⌘↩ to add and start the next card." : nil,
                      width: 520) {
            VStack(alignment: .leading, spacing: Space.lg) {
                FieldRow(label: "Front — the question or prompt") {
                    TextField("Front", text: $front, prompt: placeholder("e.g. What is the powerhouse of the cell?"), axis: .vertical)
                        .textFieldStyle(.os)
                        .lineLimit(3...8)
                        .focused($frontFocused)
                }
                FieldRow(label: "Back — the answer") {
                    TextField("Back", text: $back, prompt: placeholder("e.g. The mitochondrion"), axis: .vertical)
                        .textFieldStyle(.os)
                        .lineLimit(3...8)
                }
                FieldRow(label: "Tags (optional, separated by spaces)") {
                    TextField("Tags", text: $tags, prompt: placeholder("e.g. cells chapter3")).textFieldStyle(.os)
                }
                if addedCount > 0 {
                    Label("\(addedCount) card\(addedCount == 1 ? "" : "s") added", systemImage: "checkmark.circle.fill")
                        .font(Typo.callout).foregroundStyle(Theme.success)
                }
            }
        } footer: {
            Button("Cancel") { dismiss() }.buttonStyle(.osGhost).keyboardShortcut(.cancelAction)
            Spacer()
            if !valid {
                Text("Fill in both sides to continue")
                    .font(Typo.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            }
            if card == nil {
                Button("Add & next") { save(next: true) }
                    .buttonStyle(.osSecondary)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!valid)
            }
            Button(card == nil ? "Add card" : "Save") { save(next: false) }
                .buttonStyle(.osPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
        }
        .onAppear {
            if let card {
                front = card.front
                back = card.back
                tags = card.tags.joined(separator: " ")
            }
            frontFocused = true
        }
    }

    private var valid: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save(next: Bool) {
        guard valid else { return }
        let tagList = tags.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        if let card {
            card.front = front.trimmingCharacters(in: .whitespacesAndNewlines)
            card.back = back.trimmingCharacters(in: .whitespacesAndNewlines)
            card.tags = tagList
        } else {
            let newCard = Flashcard(front: front.trimmingCharacters(in: .whitespacesAndNewlines),
                                    back: back.trimmingCharacters(in: .whitespacesAndNewlines), tags: tagList)
            context.insert(newCard)
            newCard.deck = deck
        }
        try? context.save()
        if next {
            addedCount += 1
            front = ""
            back = ""
            frontFocused = true
        } else {
            dismiss()
        }
    }
}

// MARK: - Review

struct ReviewView: View {
    let session: ReviewSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var queue: [Flashcard] = []
    @State private var flipped = false
    @State private var reviewed = 0
    @State private var correct = 0
    @State private var started = false
    @State private var initialCount = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).font(Typo.title)
                    Text(queue.isEmpty ? "Session complete" : "\(queue.count) card\(queue.count == 1 ? "" : "s") left")
                        .font(Typo.callout).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.osGhost).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.md)

            ThinProgress(value: initialCount == 0 ? 1 : Double(reviewed) / Double(max(initialCount, reviewed + queue.count)), height: 3)
                .padding(.horizontal, Space.xxl)

            if let card = queue.first {
                cardView(card)
                    .padding(Space.xxl)
                    .frame(maxHeight: .infinity)
                controls(card)
                    .padding(.horizontal, Space.xxl)
                    .padding(.bottom, Space.xxl)
            } else {
                summary.frame(maxHeight: .infinity)
            }
        }
        .frame(width: 720, height: 580)
        .background(Theme.surface)
        .onAppear {
            guard !started else { return }
            started = true
            queue = session.cards
            initialCount = session.cards.count
        }
    }

    private func cardView(_ card: Flashcard) -> some View {
        ZStack {
            face(text: card.front, label: "Question")
                .opacity(flipped ? 0 : 1)
            face(text: card.back, label: "Answer", secondary: card.front)
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(flipped && !reduceMotion ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.flip, value: flipped)
        .onTapGesture { flipped.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to flip the card")
    }

    private func face(text: String, label: String, secondary: String? = nil) -> some View {
        VStack(spacing: Space.lg) {
            SectionLabel(label).fixedSize()
            if let secondary {
                Text(secondary).font(Typo.body).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center).lineLimit(3)
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.x3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
        .floatShadow()
    }

    @ViewBuilder private func controls(_ card: Flashcard) -> some View {
        if flipped {
            HStack(spacing: Space.md) {
                ForEach(ReviewRating.allCases) { rating in
                    Button { rate(rating, card) } label: {
                        VStack(spacing: 2) {
                            Text(rating.title).font(Typo.headline).foregroundStyle(color(rating))
                            Text("\(rating.rawValue + 1) · \(SM2.preview(for: card, rating: rating))")
                                .font(Typo.callout.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Theme.border))
                        .contentShape(Rectangle())
                        .hoverHighlight()
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue + 1)")), modifiers: [])
                    .help("\(rating.title) — next review in \(SM2.preview(for: card, rating: rating))")
                }
            }
        } else {
            Button { flipped = true } label: {
                Text("Show answer").frame(maxWidth: .infinity)
            }
            .buttonStyle(OSButtonStyle(variant: .primary, fullWidth: true))
            .keyboardShortcut(.space, modifiers: [])
            .overlay(alignment: .trailing) {
                Text("Space").font(Typo.callout).foregroundStyle(Theme.onInk.opacity(0.6)).padding(.trailing, Space.md).allowsHitTesting(false)
            }
        }
    }

    private func color(_ r: ReviewRating) -> Color {
        switch r {
        case .again: Theme.danger
        case .hard: Theme.warning
        case .good: Theme.success
        case .easy: Theme.accent
        }
    }

    private func rate(_ rating: ReviewRating, _ card: Flashcard) {
        SM2.apply(rating, to: card)
        let log = ReviewLog(rating: rating, card: card)
        context.insert(log)
        do {
            try context.save()
            PostHogSDK.shared.capture("flashcard_reviewed", properties: [
                "rating": rating.rawValue,
                "is_correct": rating.isCorrect,
            ])
        } catch {}
        reviewed += 1
        if rating.isCorrect { correct += 1 }
        flipped = false
        var q = queue
        q.removeFirst()
        if rating == .again { q.append(card) } // see it again this session
        withAnimation(Motion.fade) { queue = q }
    }

    private var summary: some View {
        VStack(spacing: Space.lg) {
            if reviewed == 0 {
                EmptyStateView(symbol: "checkmark.seal", title: "Nothing to review",
                               message: "There are no cards due right now. Come back later, or use “Practice all” in a deck.")
            } else {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 22)).foregroundStyle(Theme.success)
                    .frame(width: 52, height: 52).background(Theme.muted, in: Circle())
                Text("Session complete").font(Typo.title)
                HStack(spacing: Space.md) {
                    StatTile(value: "\(reviewed)", unit: "reviews")
                    StatTile(value: "\(Int((Double(correct) / Double(max(1, reviewed)) * 100).rounded()))%", unit: "recalled")
                }
                .frame(width: 360)
                Button("Done") { dismiss() }.buttonStyle(.osPrimary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.x3)
    }
}
