//
//  OnboardingView.swift
//  open-study
//
//  First-run setup (DESIGN.md §13 Onboarding). It is laid out exactly like
//  the app — sidebar on the canvas, questions inside the workspace card — and
//  the sidebar is a live preview that fills in as the user answers, so the
//  workspace is already theirs by the time they step into it.
//

import SwiftUI
import SwiftData

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, subjects, tools, rhythm, exams, habits, look, ready
    var id: Int { rawValue }

    /// Steps with their own Return handling (text fields) don't bind Return to Continue.
    var hasTextEntry: Bool { [.welcome, .subjects, .exams, .habits].contains(self) }
    static var questionCount: Int { allCases.count - 1 }
}

/// Shows onboarding on first launch (or when re-run from Settings), otherwise the app.
struct AppRoot: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(PrefKey.onboardingCompleted) private var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showOnboarding: Bool {
        #if DEBUG
        if UISnapshotHarness.isEnabled { return UISnapshotHarness.onboardingEnabled }
        #endif
        return !completed || router.showOnboarding
    }

    var body: some View {
        ZStack {
            if showOnboarding {
                OnboardingView(isRerun: completed)
                    .transition(.opacity)
            } else {
                ContentView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.18 : 0.3), value: showOnboarding)
    }
}

struct OnboardingView: View {
    /// Read once: finishing first-run setup marks it complete while this view
    /// is still fading out, which would otherwise flip it to re-run wording.
    @State private var isRerun: Bool

    init(isRerun: Bool) {
        _isRerun = State(initialValue: isRerun)
    }

    @Environment(AppRouter.self) private var router
    @Environment(PomodoroEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]
    @Query(sort: \Habit.sortIndex) private var habits: [Habit]
    @AppStorage(PrefKey.appearance) private var appearance = "system"

    @State private var draft: OnboardingDraft?
    @State private var step: OnboardingStep = .welcome
    /// Appearance before setup, restored if setup is skipped or cancelled.
    @State private var originalAppearance = "system"
    /// Set when saving the workspace failed; setup stays open so the user can retry.
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Layout.topStrip)
            HStack(spacing: 0) {
                OnboardingSidebarPreview(draft: draft)
                    .frame(width: Layout.sidebarWidth)
                WorkspaceCard {
                    if let draft { page(draft) }
                }
                .padding(.trailing, Space.sm)
                .padding(.bottom, Space.sm)
            }
        }
        .background(Theme.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 960, minHeight: 640)
        .alert("Open Study couldn't save your setup",
               isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your subjects, exams, habits and other settings weren't saved (the appearance you picked is already applied), and your answers are still here. Try again, or skip setup and add things from the sidebar.\n\n\(saveError ?? "")")
        }
        .onAppear {
            originalAppearance = appearance
            if draft == nil { draft = OnboardingDraft(existingSubjects: subjects, existingHabits: habits) }
        }
        #if DEBUG
        .task {
            guard UISnapshotHarness.isEnabled, UISnapshotHarness.onboardingEnabled else { return }
            await UISnapshotHarness.runOnboarding(draft: { draft }, step: { step = $0 })
        }
        #endif
    }

    // MARK: Page

    private func page(_ draft: OnboardingDraft) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(step == .ready ? "ALL SET" : "STEP \(step.rawValue + 1) OF \(OnboardingStep.questionCount)")
                    .font(Typo.label).tracking(0.6).foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                Spacer()
                if step != .ready || isRerun {
                    Button(isRerun ? "Cancel" : "Skip setup") { leave() }
                        .buttonStyle(OSButtonStyle(variant: .ghost, compact: true))
                        .help(isRerun ? "Close without changing anything" : "Start with an empty workspace. You can run setup later from Settings.")
                }
            }
            .padding(.horizontal, Space.x5)
            .padding(.top, Space.lg)

            ThinProgress(value: Double(step.rawValue + 1) / Double(OnboardingStep.questionCount), height: 2)
                .padding(.horizontal, Space.x5)
                .padding(.top, Space.sm)
                .accessibilityHidden(true)

            ScrollView {
                stepContent(draft)
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, Space.x5)
                    .padding(.top, Space.x3)
                    .padding(.bottom, Space.x3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .id(step)
            .transition(.opacity)

            Rectangle().fill(Theme.border).frame(height: 1)
            footer(draft)
                .padding(.horizontal, Space.x5)
                .padding(.vertical, Space.lg)
        }
        .animation(Motion.fade, value: step)
    }

    @ViewBuilder
    private func stepContent(_ draft: OnboardingDraft) -> some View {
        switch step {
        case .welcome: WelcomeStep(draft: draft, isRerun: isRerun, onSubmit: next)
        case .subjects: SubjectsStep(draft: draft, onSubmitEmpty: next)
        case .tools: ToolsStep(draft: draft)
        case .rhythm: RhythmStep(draft: draft)
        case .exams: ExamsStep(draft: draft)
        case .habits: HabitsStep(draft: draft)
        case .look: LookStep(draft: draft, onAppearance: { appearance = $0 })
        case .ready: ReadyStep(draft: draft, isRerun: isRerun)
        }
    }

    private func footer(_ draft: OnboardingDraft) -> some View {
        HStack(spacing: Space.sm) {
            if step != .welcome {
                Button { back() } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.osGhost)
                    .keyboardShortcut("[", modifiers: .command)
            }
            Spacer()
            if let hint = hint(draft) {
                Text(hint).font(Typo.callout).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            if step == .ready {
                Button { finish(draft) } label: {
                    Label(isRerun ? "Add to my workspace" : "Open my workspace", systemImage: "arrow.right")
                }
                .buttonStyle(.osPrimary)
                .keyboardShortcut(.defaultAction)
            } else if step.hasTextEntry {
                Button("Continue") { next() }.buttonStyle(.osPrimary)
            } else {
                Button("Continue") { next() }.buttonStyle(.osPrimary).keyboardShortcut(.defaultAction)
            }
        }
    }

    /// One quiet line beside Continue saying what happens if this step is left empty.
    private func hint(_ draft: OnboardingDraft) -> String? {
        switch step {
        case .subjects where draft.subjects.isEmpty: "You can add subjects later from the sidebar"
        case .tools where draft.tools.isEmpty: "Pages will start blank"
        case .exams where draft.exams.isEmpty: "No exams? Just continue"
        case .habits where draft.chosenHabits.isEmpty: "Habits are optional"
        default: nil
        }
    }

    // MARK: Actions

    private func next() {
        draft?.commitPending()
        guard let nextStep = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = nextStep
    }

    private func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func finish(_ draft: OnboardingDraft) {
        draft.commitPending()
        do {
            try Onboarding.apply(draft, context: context, engine: engine)
        } catch {
            saveError = error.localizedDescription
            return
        }
        router.selection = .home
        router.sidebarVisible = true
        router.showOnboarding = false
    }

    private func leave() {
        appearance = originalAppearance
        if !isRerun { Onboarding.skip() }
        router.showOnboarding = false
    }
}

// MARK: - Live sidebar preview

/// A faithful, non-interactive copy of the real sidebar (DESIGN.md §4) that
/// fills in with the user's answers.
private struct OnboardingSidebarPreview: View {
    let draft: OnboardingDraft?

    var body: some View {
        let subjects = draft?.subjects ?? []
        VStack(alignment: .leading, spacing: 0) {
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

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SidebarItem.global, id: \.self) { item in
                    SidebarRow(symbol: item.symbol, title: item.title, isActive: item == .home) {}
                }
                Text("SUBJECTS")
                    .font(Typo.label).tracking(0.6).foregroundStyle(Theme.textTertiary)
                    .frame(height: 22)
                    .padding(.leading, 10)
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.xs)
                if subjects.isEmpty {
                    SidebarRow(symbol: "plus", title: "Your subjects go here", isActive: false, muted: true) {}
                        .transition(.opacity)
                }
                ForEach(subjects) { s in
                    SidebarRow(symbol: s.symbol, title: s.name, isActive: false,
                               tint: SubjectColor.from(s.colorKey).color) {}
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Space.md)
            .animation(Motion.fade, value: subjects)

            Spacer(minLength: Space.lg)

            Text("This is your sidebar. It fills in as you answer.")
                .font(Typo.callout).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.md + 10)
                .padding(.bottom, Space.md)

            VStack(alignment: .leading, spacing: 2) {
                Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 10).padding(.bottom, Space.sm)
                SidebarRow(symbol: SidebarItem.settings.symbol, title: "Settings", isActive: false) {}
            }
            .padding(.horizontal, Space.md)
            .padding(.bottom, Space.md)
        }
        .background(Theme.canvas)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subjects.isEmpty
            ? "Sidebar preview, no subjects yet"
            : "Sidebar preview with \(subjects.map(\.name).joined(separator: ", "))")
    }
}
