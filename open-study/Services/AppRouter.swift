//
//  AppRouter.swift
//  open-study
//

import SwiftUI
import Observation

enum SidebarItem: Hashable {
    case home, calendar, tasks, flashcards, statistics, focus, settings
    case subject(UUID)
    case page(UUID)

    static let global: [SidebarItem] = [.home, .calendar, .tasks, .flashcards, .statistics, .focus]

    var title: String {
        switch self {
        case .home: "Home"
        case .calendar: "Calendar"
        case .tasks: "Tasks"
        case .flashcards: "Flashcards"
        case .statistics: "Statistics"
        case .focus: "Focus"
        case .settings: "Settings"
        case .subject: "Subject"
        case .page: "Page"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .flashcards: "rectangle.on.rectangle.angled"
        case .statistics: "chart.bar.xaxis"
        case .focus: "timer"
        case .settings: "gearshape"
        case .subject: "book.closed"
        case .page: "doc.text"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selection: SidebarItem = .home {
        didSet { if selection != .focus { lastNonFocus = selection } }
    }
    var sidebarVisible: Bool = UserDefaults.standard.object(forKey: PrefKey.sidebarVisible) as? Bool ?? true {
        didSet { UserDefaults.standard.set(sidebarVisible, forKey: PrefKey.sidebarVisible) }
    }
    /// Deck to open when navigating to Flashcards from elsewhere.
    var pendingDeckID: UUID?
    /// Triggers the "new subject" popover in the sidebar.
    var showNewSubject = false
    private(set) var lastNonFocus: SidebarItem = .home

    /// Subjects whose topic pages are listed in the sidebar (persisted).
    var expandedSubjects: Set<UUID> = Set(
        (UserDefaults.standard.stringArray(forKey: "sidebar.expandedSubjects") ?? []).compactMap(UUID.init)
    ) {
        didSet { UserDefaults.standard.set(expandedSubjects.map(\.uuidString), forKey: "sidebar.expandedSubjects") }
    }

    var isFocusMode: Bool { selection == .focus }

    func exitFocus() {
        withAnimation(Motion.sidebar) { selection = lastNonFocus }
    }

    func openDeck(_ id: UUID) {
        pendingDeckID = id
        selection = .flashcards
    }
}
