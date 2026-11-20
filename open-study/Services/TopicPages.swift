//
//  TopicPages.swift
//  open-study
//
//  Create / move / delete topic pages. Shared by the sidebar and the
//  subject page so both behave identically.
//

import SwiftUI
import SwiftData
import PostHog

@MainActor
enum TopicPages {
    static let symbols = [
        "doc.text", "doc.richtext", "list.bullet.rectangle", "lightbulb", "bookmark", "flag",
        "star", "graduationcap", "pencil", "book", "brain", "function",
    ]

    /// Adds an empty page at the end of the subject's list and opens it.
    @discardableResult
    static func create(in subject: Subject, context: ModelContext, router: AppRouter) -> TopicPage {
        let page = TopicPage(sortIndex: (subject.pages.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(page)
        page.subject = subject
        do {
            try context.save()
            PostHogSDK.shared.capture("page_created")
        } catch {}
        router.expandedSubjects.insert(subject.id)
        router.selection = .page(page.id)
        return page
    }

    static func delete(_ page: TopicPage, context: ModelContext, router: AppRouter) {
        if router.selection == .page(page.id) {
            router.selection = page.subject.map { .subject($0.id) } ?? .home
        }
        context.delete(page)
        try? context.save()
    }

    /// Reorders within a subject, or moves the page into `subject` when it
    /// belongs to another one.
    ///
    /// Moving between subjects, what follows the page:
    /// - its blocks;
    /// - tasks in its task lists that still belong to the old subject (task
    ///   lists add tasks under the block's subject, so the list stays in one
    ///   subject and both subjects' statistics stay consistent). Tasks the
    ///   user assigned to some other subject keep that choice.
    ///
    /// What stays put: decks, quizzes and documents (they can be shared with
    /// other pages) and history (focus sessions, review logs).
    static func move(_ page: TopicPage, to subject: Subject, before target: TopicPage?) {
        // Dropping a page onto itself is a no-op (nil target still means "move to end").
        if target?.id == page.id { return }
        if page.subject?.id != subject.id {
            let oldSubjectID = page.subject?.id
            page.subject = subject
            for block in page.blocks {
                block.subject = subject
                for task in block.tasks where task.subject?.id == oldSubjectID {
                    task.subject = subject
                }
            }
        }
        var ordered = subject.sortedPages.filter { $0.id != page.id }
        let index = target.flatMap { t in ordered.firstIndex(where: { $0.id == t.id }) } ?? ordered.count
        ordered.insert(page, at: index)
        withAnimation(Motion.fade) {
            for (i, p) in ordered.enumerated() { p.sortIndex = i }
        }
    }

    static func shift(_ page: TopicPage, by delta: Int) {
        guard let subject = page.subject else { return }
        var ordered = subject.sortedPages
        guard let i = ordered.firstIndex(where: { $0.id == page.id }) else { return }
        let j = i + delta
        guard ordered.indices.contains(j) else { return }
        ordered.swapAt(i, j)
        withAnimation(Motion.fade) {
            for (k, p) in ordered.enumerated() { p.sortIndex = k }
        }
    }

    static let deleteMessage = "The page and its blocks will be deleted. Tasks, flashcard decks, quizzes and documents used on it are kept."}
