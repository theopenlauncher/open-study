//
//  ContentView.swift
//  open-study
//
//  Root window shell: cream top strip + sidebar on the canvas, with the
//  active screen inside an inset off-white workspace card (DESIGN.md §4–5).
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PomodoroEngine.self) private var engine
    @Environment(\.modelContext) private var context

    private var showSidebar: Bool { router.sidebarVisible && !router.isFocusMode }

    var body: some View {
        VStack(spacing: 0) {
            TopStrip()
            HStack(spacing: 0) {
                if showSidebar {
                    SidebarView()
                        .frame(width: Layout.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                WorkspaceCard {
                    DetailView()
                }
                .padding(.leading, showSidebar ? 0 : Space.sm)
                .padding(.trailing, Space.sm)
                .padding(.bottom, Space.sm)
            }
        }
        .background(Theme.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 960, minHeight: 640)
        .animation(Motion.sidebar, value: showSidebar)
        .onAppear {
            engine.modelContext = context
        }
        #if DEBUG
        .task {
            guard UISnapshotHarness.isEnabled else { return }
            UISnapshotHarness.seed(context)
            await UISnapshotHarness.run(router: router) {
                try? context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\.sortIndex)])).first?.id
            }
        }
        #endif
    }
}

private struct WorkspaceCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.window, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.window, style: .continuous).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(shadowOpacity), radius: 1, y: 0.5)
            .shadow(color: .black.opacity(shadowOpacity * 0.75), radius: 8, y: 2)
    }

    private var shadowOpacity: Double {
        #if DEBUG
        // Offscreen snapshot rendering can't capture shadowed layers.
        if UISnapshotHarness.isEnabled { return 0 }
        #endif
        return 0.04
    }
}

private struct DetailView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            switch router.selection {
            case .home: HomeView()
            case .calendar: CalendarView()
            case .tasks: TasksView()
            case .flashcards: FlashcardsView()
            case .statistics: StatisticsView()
            case .focus: FocusView()
            case .settings: SettingsView()
            case .subject(let id): SubjectPageLoader(subjectID: id)
            }
        }
        .id(router.selection)
        .transition(.opacity)
        .animation(Motion.fade, value: router.selection)
    }
}

// MARK: - Top strip

private struct TopStrip: View {
    @Environment(AppRouter.self) private var router
    @Environment(PomodoroEngine.self) private var engine

    var body: some View {
        HStack(spacing: Space.sm) {
            Color.clear.frame(width: 70) // traffic lights
            if !router.isFocusMode {
                IconButton(symbol: "sidebar.left", help: router.sidebarVisible ? "Hide sidebar (⌃⌘S)" : "Show sidebar (⌃⌘S)", onCanvas: true) {
                    withAnimation(Motion.sidebar) { router.sidebarVisible.toggle() }
                }
            }
            Spacer()
            if engine.isActive && !router.isFocusMode {
                TimerPill()
                    .transition(.opacity)
            }
        }
        .padding(.trailing, Space.md)
        .frame(height: Layout.topStrip, alignment: .center)
        .padding(.top, 1)
        .animation(Motion.fade, value: engine.isActive)
    }
}

/// Live timer status shown in the top strip; click to enter Focus.
struct TimerPill: View {
    @Environment(AppRouter.self) private var router
    @Environment(PomodoroEngine.self) private var engine

    var body: some View {
        Button {
            withAnimation(Motion.sidebar) { router.selection = .focus }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.phase == .focus ? Theme.ink : Theme.success)
                    .frame(width: 6, height: 6)
                    .opacity(engine.isRunning ? 1 : 0.4)
                Text(Fmt.clock(engine.remaining))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text(engine.isRunning ? engine.phase.title : "Paused")
                    .font(Typo.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .help("Open Focus mode")
    }
}
