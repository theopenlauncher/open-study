//
//  TopicPageView.swift
//  open-study
//
//  A topic page inside a subject: a back link to the subject, an editable
//  title and the same block canvas as the subject page.
//

import SwiftUI
import SwiftData

struct TopicPageLoader: View {
    let pageID: UUID
    @Query private var pages: [TopicPage]

    init(pageID: UUID) {
        self.pageID = pageID
        _pages = Query(filter: #Predicate<TopicPage> { $0.id == pageID })
    }

    var body: some View {
        if let page = pages.first {
            BlockCanvas(owner: .page(page),
                        emptyHint: "This page is empty. Press / or click + to add notes, flashcards, tasks, a PDF and more.") {
                TopicPageHeader(page: page)
            }
        } else {
            EmptyStateView(symbol: "questionmark.folder", title: "Page not found",
                           message: "This page may have been deleted.")
                .frame(maxHeight: .infinity)
        }
    }
}

private struct TopicPageHeader: View {
    @Bindable var page: TopicPage
    @Environment(AppRouter.self) private var router
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if let subject = page.subject {
                // In-page back link (DESIGN.md §5 drill-downs).
                Button { router.selection = .subject(subject.id) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Image(systemName: subject.symbol)
                            .foregroundStyle(SubjectColor.from(subject.colorKey).color)
                        Text(subject.name.isEmpty ? "Untitled" : subject.name)
                    }
                    .font(Typo.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .hoverHighlight(cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .padding(.leading, -6)
                .help("Back to \(subject.name)")
            }

            Menu {
                ForEach(TopicPages.symbols, id: \.self) { s in
                    Button { page.symbol = s } label: { Label(s, systemImage: s) }
                }
            } label: {
                Image(systemName: page.symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(page.subject.map { SubjectColor.from($0.colorKey).color } ?? Theme.textSecondary)
                    .frame(height: 36)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change icon")

            TextField("Untitled page", text: $page.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 36, weight: .regular, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .focused($titleFocused)
        }
        .onAppear {
            // Reveal this page in the sidebar however it was opened.
            if let id = page.subject?.id, !router.expandedSubjects.contains(id) {
                router.expandedSubjects.insert(id)
            }
            // New pages start with the title ready to type into.
            if page.title.isEmpty && page.blocks.isEmpty {
                DispatchQueue.main.async { titleFocused = true }
            }
        }
    }
}
