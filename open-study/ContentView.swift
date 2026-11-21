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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var showSidebar: Bool { router.sidebarVisible && !router.isFocusMode }

    private var promptShown: Binding<Bool> {
        Binding(get: { engine.prompt != nil }, set: { if !$0 { engine.dismissPrompt() } })
    }

    private var promptTitle: String {
        guard let prompt = engine.prompt else { return "" }
        return prompt.finished == .focus ? "Focus session complete" : "Break's over"
    }

    var body: some View {
        VStack(spacing: 0) {
            TopStrip()
            HStack(spacing: 0) {
                // The sidebar stays in the layout and its slot animates between
                // 0 and full width, so it slides out while the workspace card
                // widens in the same motion (DESIGN.md §4). Removing it from the
                // hierarchy instead made the card jump.
                SidebarView()
                    .frame(width: Layout.sidebarWidth)
                    .offset(x: showSidebar || reduceMotion ? 0 : -Layout.sidebarWidth)
                    .opacity(showSidebar ? 1 : 0)
                    .frame(width: showSidebar ? Layout.sidebarWidth : 0, alignment: .leading)
                    .clipped()
                    .allowsHitTesting(showSidebar)
                    .accessibilityHidden(!showSidebar)
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
        .animation(reduceMotion ? Motion.fade : Motion.sidebar, value: showSidebar)
        .onAppear {
            engine.modelContext = context
        }
        .alert(promptTitle, isPresented: promptShown, presenting: engine.prompt) { prompt in
            if prompt.next == .focus {
                Button("Start Session \(prompt.sessionNumber)") { engine.acceptPrompt() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Start \(prompt.nextMinutes)-min Break") { engine.acceptPrompt() }
                    .keyboardShortcut(.defaultAction)
                Button("Skip Break") { engine.skipBreakFromPrompt() }
            }
            Button("Later", role: .cancel) { engine.dismissPrompt() }
        } message: { prompt in
            Text(prompt.next == .focus
                 ? "Ready for focus session \(prompt.sessionNumber)? It runs for \(prompt.nextMinutes) minutes."
                 : "Nice work. Take a \(prompt.nextMinutes)-minute \(prompt.next == .longBreak ? "long break" : "break") before the next session.")
        }
        #if DEBUG
        .task {
            guard UISnapshotHarness.isEnabled else { return }
            UISnapshotHarness.container = context.container
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
            case .page(let id): TopicPageLoader(pageID: id)
            }
        }
        .id(router.selection)
        // Swap sections instantly. A cross-fade kept both screens alive and
        // delayed the new one becoming visible; `.identity` also keeps callers
        // that wrap the change in `withAnimation` (Focus mode) from fading it,
        // while the sidebar still slides via ContentView's own animation.
        .transition(.identity)
    }
}

// MARK: - Top strip

private struct TopStrip: View {
    @Environment(AppRouter.self) private var router
    @Environment(PomodoroEngine.self) private var engine

    var body: some View {
        HStack(spacing: Space.sm) {
            Color.clear.frame(width: 70) // traffic lights
            // Only needed to bring the sidebar back: while it's open, its own
            // brand-row button hides it.
            if !router.isFocusMode && !router.sidebarVisible {
                IconButton(symbol: "sidebar.left", help: "Show sidebar (⌃⌘S)", onCanvas: true) {
                    withAnimation(Motion.sidebar) { router.sidebarVisible = true }
                }
                .transition(.opacity)
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
        .animation(Motion.fade, value: router.sidebarVisible)
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
