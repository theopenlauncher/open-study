//
//  PDFReader.swift
//  open-study
//
//  Native PDFKit reader with highlights and sticky notes. Annotations are
//  written back into the app's stored copy of the PDF.
//

import SwiftUI
import SwiftData
import PDFKit

@MainActor
@Observable
final class PDFController {
    @ObservationIgnored weak var view: PDFView?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored var onPageChange: ((Int) -> Void)?
    @ObservationIgnored var onAnnotationsChanged: (() -> Void)?

    var pageIndex = 0
    var pageCount = 0
    var hasSelection = false
    var annotationsVersion = 0

    func attach(_ view: PDFView) {
        self.view = view
        pageCount = view.document?.pageCount ?? 0
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = [
            NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncPage() }
            },
            NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hasSelection = !(self.view?.currentSelection?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            },
        ]
        syncPage()
    }

    private func syncPage() {
        guard let view, let doc = view.document, let page = view.currentPage else { return }
        pageIndex = doc.index(for: page)
        pageCount = doc.pageCount
        onPageChange?(pageIndex)
    }

    func go(to index: Int) {
        guard let view, let doc = view.document, let page = doc.page(at: max(0, min(index, doc.pageCount - 1))) else { return }
        view.go(to: page)
    }

    func next() { view?.goToNextPage(nil) }
    func previous() { view?.goToPreviousPage(nil) }
    func zoomIn() { view?.zoomIn(nil) }
    func zoomOut() { view?.zoomOut(nil) }
    func fit() { view?.autoScales = true }

    func highlightSelection() {
        guard let view, let selection = view.currentSelection else { return }
        for line in selection.selectionsByLine() {
            guard let page = line.pages.first else { continue }
            let bounds = line.bounds(for: page)
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = NSColor.systemYellow.withAlphaComponent(0.45)
            page.addAnnotation(annotation)
        }
        view.clearSelection()
        changed()
    }

    func addNote(_ text: String) {
        guard let view, let page = view.currentPage else { return }
        let origin: CGPoint
        if let selection = view.currentSelection, let selPage = selection.pages.first, selPage == page {
            let b = selection.bounds(for: page)
            origin = CGPoint(x: b.maxX + 4, y: b.maxY - 18)
        } else {
            let box = page.bounds(for: .cropBox)
            origin = CGPoint(x: box.maxX - 40, y: box.maxY - 40)
        }
        let note = PDFAnnotation(bounds: CGRect(origin: origin, size: CGSize(width: 20, height: 20)), forType: .text, withProperties: nil)
        note.contents = text
        note.color = NSColor.systemYellow
        page.addAnnotation(note)
        changed()
    }

    struct Item: Identifiable {
        let id = UUID()
        let annotation: PDFAnnotation
        let pageIndex: Int
        let isNote: Bool
        let text: String
    }

    func items() -> [Item] {
        _ = annotationsVersion
        guard let doc = view?.document else { return [] }
        var result: [Item] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            for a in page.annotations {
                let type = a.type ?? ""
                if type == "Highlight" {
                    let text = page.selection(for: a.bounds.insetBy(dx: 0, dy: a.bounds.height * 0.2))?.string ?? ""
                    result.append(Item(annotation: a, pageIndex: i, isNote: false, text: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else if type == "Text" {
                    result.append(Item(annotation: a, pageIndex: i, isNote: true, text: a.contents ?? ""))
                }
            }
        }
        return result
    }

    func remove(_ item: Item) {
        item.annotation.page?.removeAnnotation(item.annotation)
        changed()
    }

    func updateNote(_ item: Item, text: String) {
        item.annotation.contents = text
        changed()
    }

    func reveal(_ item: Item) {
        guard let page = item.annotation.page else { return }
        view?.go(to: item.annotation.bounds, on: page)
    }

    private func changed() {
        annotationsVersion += 1
        onAnnotationsChanged?()
    }

    func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}

struct PDFKitView: NSViewRepresentable {
    let pdf: PDFDocument
    let controller: PDFController
    let startPage: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = pdf
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.backgroundColor = dynamicNSColor(light: 0xF2EFE8, dark: 0x1C1B19)
        controller.attach(view)
        if startPage > 0, let page = pdf.page(at: min(startPage, pdf.pageCount - 1)) {
            DispatchQueue.main.async { view.go(to: page) }
        }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== pdf {
            view.document = pdf
            controller.attach(view)
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: ()) {}
}

/// Reader with toolbar. Used inline in PDF blocks and in the reader window.
struct PDFReader: View {
    @Bindable var document: StudyDocument
    var compact = false
    var onRemove: (() -> Void)? = nil

    @Environment(\.openWindow) private var openWindow
    @State private var controller = PDFController()
    @State private var pdf: PDFDocument?
    @State private var missing = false
    @State private var error: String?
    @State private var showNote = false
    @State private var noteText = ""
    @State private var showAnnotations = false

    var body: some View {
        VStack(spacing: 0) {
            if missing {
                missingView
            } else if let pdf {
                toolbar
                Divider().overlay(Theme.border)
                PDFKitView(pdf: pdf, controller: controller, startPage: document.lastPage)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Opening PDF…").font(Typo.callout).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: load)
        .onDisappear {
            DocumentStore.shared.saveNow(fileName: document.fileName)
            controller.detach()
        }
    }

    private func load() {
        guard DocumentStore.shared.fileExists(document) else { missing = true; return }
        guard let loaded = DocumentStore.shared.pdf(for: document) else { missing = true; return }
        missing = false
        pdf = loaded
        controller.onPageChange = { [document] page in document.lastPage = page }
        controller.onAnnotationsChanged = { [document] in DocumentStore.shared.scheduleSave(document) }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Image(systemName: "doc.richtext").font(.system(size: 13)).foregroundStyle(Theme.textSecondary).padding(.leading, 6)
            Text(document.title)
                .font(Typo.headline)
                .lineLimit(1)
                .frame(maxWidth: compact ? 180 : 320, alignment: .leading)
                .padding(.horizontal, 6)
                .help(document.title)
            IconButton(symbol: "chevron.up", help: "Previous page", size: 26) { controller.previous() }
            IconButton(symbol: "chevron.down", help: "Next page", size: 26) { controller.next() }
            Text(controller.pageCount > 0 ? "\(controller.pageIndex + 1) / \(controller.pageCount)" : "")
                .font(Typo.callout.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 54)
            Rectangle().fill(Theme.border).frame(width: 1, height: 16).padding(.horizontal, 4)
            IconButton(symbol: "minus.magnifyingglass", help: "Zoom out", size: 26) { controller.zoomOut() }
            IconButton(symbol: "plus.magnifyingglass", help: "Zoom in", size: 26) { controller.zoomIn() }
            IconButton(symbol: "arrow.up.left.and.down.right.magnifyingglass", help: "Fit to width", size: 26) { controller.fit() }
            Spacer(minLength: Space.sm)
            Button { controller.highlightSelection() } label: {
                Label("Highlight", systemImage: "highlighter")
            }
            .buttonStyle(OSButtonStyle(variant: .ghost, compact: true))
            .disabled(!controller.hasSelection)
            .help(controller.hasSelection ? "Highlight the selected text" : "Select text in the PDF to highlight it")
            Button { noteText = ""; showNote = true } label: {
                Label("Note", systemImage: "note.text.badge.plus")
            }
            .buttonStyle(OSButtonStyle(variant: .ghost, compact: true))
            .help("Add a note to this page")
            .popover(isPresented: $showNote, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Note on page \(controller.pageIndex + 1)").font(Typo.headline)
                    TextField("Write a note", text: $noteText, axis: .vertical)
                        .textFieldStyle(.os)
                        .lineLimit(3...6)
                        .frame(width: 260)
                    HStack {
                        Spacer()
                        Button("Add note") {
                            controller.addNote(noteText)
                            showNote = false
                        }
                        .buttonStyle(.osPrimary)
                        .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(Space.lg)
            }
            IconButton(symbol: "list.bullet.rectangle", help: "Highlights and notes", size: 26) { showAnnotations = true }
                .popover(isPresented: $showAnnotations, arrowEdge: .bottom) {
                    AnnotationList(controller: controller)
                }
            if compact {
                IconButton(symbol: "macwindow", help: "Open in its own window", size: 26) {
                    openWindow(id: "pdf", value: document.id)
                }
            }
        }
        .padding(.horizontal, Space.sm)
        .frame(height: 40)
    }

    private var missingView: some View {
        VStack(spacing: Space.md) {
            InlineErrorView(message: "The file for “\(document.title)” is missing from Open Study's storage. Choose the original PDF to relink it.")
            if let error { Text(error).font(Typo.callout).foregroundStyle(Theme.danger) }
            HStack {
                Button("Choose File…") {
                    guard let url = DocumentStore.shared.choosePDF() else { return }
                    do {
                        try DocumentStore.shared.relink(document, to: url)
                        error = nil
                        load()
                    } catch let e {
                        error = e.localizedDescription
                    }
                }
                .buttonStyle(.osSecondary)
                if let onRemove {
                    Button("Remove Block", role: .destructive, action: onRemove).buttonStyle(.osDestructive)
                }
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AnnotationList: View {
    let controller: PDFController

    var body: some View {
        let items = controller.items()
        VStack(alignment: .leading, spacing: 0) {
            Text("Highlights & notes").font(Typo.headline).padding(Space.md)
            Divider().overlay(Theme.border)
            if items.isEmpty {
                Text("Select text and choose Highlight, or add a Note to a page. They'll be listed here and saved inside the PDF.")
                    .font(Typo.callout).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.md)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            AnnotationRow(item: item, controller: controller)
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
        .frame(width: 320)
    }
}

private struct AnnotationRow: View {
    let item: PDFController.Item
    let controller: PDFController
    @State private var text = ""

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: item.isNote ? "note.text" : "highlighter")
                .font(.system(size: 12))
                .foregroundStyle(item.isNote ? Theme.warning : Theme.textSecondary)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Page \(item.pageIndex + 1)").font(Typo.label).foregroundStyle(Theme.textTertiary)
                if item.isNote {
                    TextField("Note", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Typo.body)
                        .onSubmit { controller.updateNote(item, text: text) }
                        .onChange(of: text) { _, new in controller.updateNote(item, text: new) }
                } else {
                    Text(item.text.isEmpty ? "Highlight" : item.text).font(Typo.body).lineLimit(3)
                }
            }
            Spacer()
            ItemDeleteButton { controller.remove(item) }
        }
        .padding(Space.md)
        .contentShape(Rectangle())
        .onTapGesture { controller.reveal(item) }
        .hoverHighlight(cornerRadius: 0)
        .onAppear { text = item.text }
    }
}

struct PDFReaderWindow: View {
    let documentID: UUID
    @Query private var documents: [StudyDocument]

    init(documentID: UUID) {
        self.documentID = documentID
        _documents = Query(filter: #Predicate<StudyDocument> { $0.id == documentID })
    }

    var body: some View {
        Group {
            if let doc = documents.first {
                PDFReader(document: doc)
                    .navigationTitle(doc.title)
            } else {
                EmptyStateView(symbol: "doc.questionmark", title: "Document not found", message: "This PDF may have been removed.")
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .background(Theme.surface)
    }
}
