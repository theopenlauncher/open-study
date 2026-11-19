//
//  ImportCardsView.swift
//  open-study
//
//  Anki-style text import in three plain-language steps:
//  1 Source → 2 Columns → 3 Preview & import.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportCardsView: View {
    let preselectedDeck: Deck?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt) private var decks: [Deck]

    @State private var rawText = ""
    @State private var sourceName: String?
    @State private var separator: ImportSeparator = .auto
    @State private var customSeparator = "::"
    @State private var hasHeader = false
    @State private var mapping: [ImportField] = []
    @State private var deckID: UUID?
    @State private var newDeckName = ""
    @State private var skipDuplicates = true
    @State private var errorMessage: String?
    @State private var importedSummary: String?

    private static let newDeckTag = UUID()

    // MARK: Derived

    private var effectiveSeparator: String {
        switch separator {
        case .auto: CardImporter.detectSeparator(rawText)
        case .comma: ","
        case .tab: "\t"
        case .semicolon: ";"
        case .pipe: "|"
        case .custom: customSeparator.isEmpty ? "::" : customSeparator
        }
    }

    private var allRows: [[String]] { CardImporter.parse(rawText, separator: effectiveSeparator) }
    private var dataRows: [[String]] { hasHeader ? Array(allRows.dropFirst()) : allRows }
    private var header: [String]? { hasHeader ? allRows.first : nil }
    private var columnCount: Int { allRows.map(\.count).max() ?? 0 }

    private var targetDeck: Deck? {
        if deckID == Self.newDeckTag { return nil }
        return decks.first { $0.id == deckID }
    }

    private var candidates: [CardImporter.Candidate] {
        let existing = Set((targetDeck?.cards ?? []).map { CardImporter.normalize($0.front) })
        return CardImporter.candidates(rows: dataRows, mapping: mapping, existingFronts: existing)
    }

    private var importable: [CardImporter.Candidate] {
        candidates.filter { $0.isValid && (!skipDuplicates || !$0.isDuplicate) }
    }

    private var mappingValid: Bool { mapping.contains(.front) && mapping.contains(.back) }
    private var deckValid: Bool { deckID == Self.newDeckTag ? !newDeckName.trimmingCharacters(in: .whitespaces).isEmpty : targetDeck != nil }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import flashcards").font(Typo.title)
                Text("Bring in cards from a spreadsheet (CSV) or a text file where each line is one card, with the front and back separated by a comma, tab or other character.")
                    .font(Typo.body).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.lg)

            Divider().overlay(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    step(1, "Choose your cards", help: "Pick a .csv or .txt file, or paste text directly. Lines starting with # are ignored.") { sourceStep }
                    if !rawText.isEmpty {
                        step(2, "Match the columns", help: "Tell Open Study which column is the front (question) and which is the back (answer). Anything else can be tags or ignored.") { columnsStep }
                        step(3, "Preview and choose a deck", help: "Check the cards look right. Rows with problems are skipped automatically.") { previewStep }
                    }
                    if let errorMessage { InlineErrorView(message: errorMessage) }
                }
                .padding(Space.xxl)
            }

            Divider().overlay(Theme.border)
            footer
                .padding(.horizontal, Space.xxl)
                .padding(.vertical, Space.lg)
        }
        .frame(width: 780, height: 680)
        .background(Theme.surface)
        .onAppear {
            deckID = preselectedDeck?.id ?? decks.first?.id ?? Self.newDeckTag
        }
        .onChange(of: columnCount) { refreshMapping() }
        .onChange(of: hasHeader) { refreshMapping() }
    }

    private func step<Content: View>(_ n: Int, _ title: String, help: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: Space.lg) {
            Text("\(n)")
                .font(Typo.headline)
                .foregroundStyle(Theme.onInk)
                .frame(width: 24, height: 24)
                .background(Theme.ink, in: Circle())
            VStack(alignment: .leading, spacing: Space.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.headline)
                    Text(help).font(Typo.callout).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
        }
    }

    // MARK: Step 1

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                Button { chooseFile() } label: { Label("Choose file…", systemImage: "doc") }
                    .buttonStyle(.osSecondary)
                if let sourceName {
                    Label(sourceName, systemImage: "checkmark.circle.fill")
                        .font(Typo.callout).foregroundStyle(Theme.success)
                }
                Spacer()
                if !rawText.isEmpty {
                    Button("Clear") { rawText = ""; sourceName = nil; errorMessage = nil }.buttonStyle(.osGhost)
                }
            }
            TextEditor(text: $rawText)
                .font(Typo.mono)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 120)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Theme.border))
                .overlay(alignment: .topLeading) {
                    if rawText.isEmpty {
                        Text("…or paste here, for example:\nmitochondria, powerhouse of the cell\nosmosis, movement of water across a membrane")
                            .font(Typo.mono).foregroundStyle(Theme.textTertiary).padding(13).allowsHitTesting(false)
                    }
                }
                .onChange(of: rawText) { _, new in
                    if !new.isEmpty, let first = allRows.first, CardImporter.looksLikeHeader(first) { hasHeader = true }
                }
        }
    }

    // MARK: Step 2

    private var columnsStep: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.lg) {
                Picker("Separator", selection: $separator) {
                    ForEach(ImportSeparator.allCases) { s in Text(s.title).tag(s) }
                }
                .fixedSize()
                if separator == .custom {
                    TextField("e.g. ::", text: $customSeparator).textFieldStyle(.os).frame(width: 80)
                }
                if separator == .auto {
                    Text("Detected: \(separatorName(effectiveSeparator))").font(Typo.callout).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Toggle("First row is a header", isOn: $hasHeader).toggleStyle(.checkbox)
            }

            if columnCount == 0 {
                Text("No rows found yet.").font(Typo.callout).foregroundStyle(Theme.textTertiary)
            } else {
                HStack(alignment: .top, spacing: Space.md) {
                    ForEach(0..<min(columnCount, mapping.count), id: \.self) { col in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(header?[safe: col].flatMap { $0.isEmpty ? nil : $0 } ?? "Column \(col + 1)")
                                .font(Typo.callout.weight(.medium)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            Picker("Column \(col + 1)", selection: Binding(get: { mapping[col] }, set: { mapping[col] = $0 })) {
                                ForEach(ImportField.allCases) { f in Text(f.title).tag(f) }
                            }
                            .labelsHidden()
                            Text(dataRows.first?[safe: col] ?? "")
                                .font(Typo.callout).foregroundStyle(Theme.textTertiary).lineLimit(2)
                        }
                        .padding(Space.md)
                        .frame(width: 160, alignment: .leading)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Theme.border))
                    }
                }
                if !mappingValid {
                    Label("Choose one column for Front and one for Back.", systemImage: "exclamationmark.circle")
                        .font(Typo.callout).foregroundStyle(Theme.warning)
                }
            }
        }
    }

    // MARK: Step 3

    private var previewStep: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.md) {
                Picker("Add to deck", selection: $deckID) {
                    ForEach(decks) { d in Text(d.name).tag(UUID?.some(d.id)) }
                    if !decks.isEmpty { Divider() }
                    Text("New deck…").tag(UUID?.some(Self.newDeckTag))
                }
                .fixedSize()
                if deckID == Self.newDeckTag {
                    TextField("New deck name", text: $newDeckName).textFieldStyle(.os).frame(width: 200)
                }
                Spacer()
                Toggle("Skip duplicates", isOn: $skipDuplicates).toggleStyle(.checkbox)
                    .help("A card is a duplicate when its front matches a card already in the deck or earlier in the file.")
            }

            let list = candidates
            let invalid = list.filter { !$0.isValid }.count
            let dupes = list.filter { $0.isDuplicate }.count
            HStack(spacing: Space.lg) {
                summaryChip("\(list.filter { $0.status == .ready }.count) ready", Theme.success)
                if dupes > 0 { summaryChip("\(dupes) duplicate\(dupes == 1 ? "" : "s")", Theme.warning) }
                if invalid > 0 { summaryChip("\(invalid) incomplete", Theme.danger) }
            }

            if mappingValid && !list.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        Text("#").frame(width: 30, alignment: .leading)
                        Text("Front").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Back").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Status").frame(width: 120, alignment: .leading)
                    }
                    .font(Typo.label).tracking(0.4).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, Space.md).padding(.vertical, 8)
                    ForEach(list.prefix(100)) { c in
                        Rectangle().fill(Theme.border).frame(height: 1)
                        HStack(alignment: .top) {
                            Text("\(c.line)").frame(width: 30, alignment: .leading).foregroundStyle(Theme.textTertiary)
                            Text(c.front.isEmpty ? "—" : c.front).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                            Text(c.back.isEmpty ? "—" : c.back).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                                .foregroundStyle(Theme.textSecondary)
                            Text(c.statusText).frame(width: 120, alignment: .leading)
                                .foregroundStyle(c.status == .ready ? Theme.success : c.isDuplicate ? Theme.warning : Theme.danger)
                        }
                        .font(Typo.callout)
                        .padding(.horizontal, Space.md).padding(.vertical, 7)
                        .opacity(c.isValid && !(skipDuplicates && c.isDuplicate) ? 1 : 0.6)
                    }
                    if list.count > 100 {
                        Text("…and \(list.count - 100) more rows").font(Typo.callout).foregroundStyle(Theme.textTertiary).padding(Space.md)
                    }
                }
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Theme.border))
            }
        }
    }

    private func summaryChip(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(Typo.callout).foregroundStyle(Theme.textSecondary)
        }
    }

    private var footer: some View {
        HStack {
            if let importedSummary {
                Label(importedSummary, systemImage: "checkmark.circle.fill").font(Typo.callout).foregroundStyle(Theme.success)
            }
            Spacer()
            Button(importedSummary == nil ? "Cancel" : "Close") { dismiss() }.buttonStyle(.osGhost).keyboardShortcut(.cancelAction)
            Button("Import \(importable.count) card\(importable.count == 1 ? "" : "s")", action: performImport)
                .buttonStyle(.osPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!mappingValid || !deckValid || importable.isEmpty)
        }
    }

    // MARK: Actions

    private func separatorName(_ s: String) -> String {
        switch s {
        case "\t": "Tab"
        case ",": "Comma"
        case ";": "Semicolon"
        case "|": "Pipe"
        default: "“\(s)”"
        }
    }

    private func refreshMapping() {
        mapping = CardImporter.defaultMapping(columns: columnCount, header: header)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText, .text, .utf8PlainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a CSV or text file with one card per line."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var encoding = String.Encoding.utf8
            let text: String
            if let t = try? String(contentsOf: url, usedEncoding: &encoding) { text = t }
            else { text = try String(contentsOf: url, encoding: .isoLatin1) }
            rawText = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
            sourceName = url.lastPathComponent
            errorMessage = nil
            if url.pathExtension.lowercased() == "csv" { separator = .comma }
            hasHeader = allRows.first.map { CardImporter.looksLikeHeader($0) } ?? false
            refreshMapping()
        } catch {
            errorMessage = "That file couldn't be read as text. Save it as UTF-8 CSV or plain text and try again."
        }
    }

    private func performImport() {
        var deck = targetDeck
        if deck == nil {
            let d = Deck(name: newDeckName.trimmingCharacters(in: .whitespaces))
            context.insert(d)
            deck = d
            deckID = d.id
        }
        guard let deck else { return }
        let toImport = importable
        for c in toImport {
            let card = Flashcard(front: c.front, back: c.back, tags: c.tags)
            context.insert(card)
            card.deck = deck
        }
        do {
            try context.save()
            let skipped = candidates.count - toImport.count
            importedSummary = "Imported \(toImport.count) into \(deck.name)" + (skipped > 0 ? " · \(skipped) skipped" : "")
            rawText = ""
            sourceName = nil
        } catch {
            errorMessage = "The cards couldn't be saved: \(error.localizedDescription)"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
