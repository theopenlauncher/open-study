//
//  FocusView.swift
//  open-study
//
//  Distraction-free focus mode inside the app (it does not block other apps).
//

import SwiftUI
import SwiftData

struct TimerRing: View {
    let progress: Double
    var lineWidth: CGFloat = 4
    var tint: Color = Theme.ink

    var body: some View {
        ZStack {
            Circle().stroke(Theme.border, lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
        }
        .accessibilityHidden(true)
    }
}

struct PhasePicker: View {
    @Environment(PomodoroEngine.self) private var engine
    var body: some View {
        OSSegmented(options: PomodoroPhase.allCases.map { ($0, $0.title) },
                    selection: Binding(get: { engine.phase }, set: { engine.select($0) }))
    }
}

struct FocusView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PomodoroEngine.self) private var engine
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]
    @Query(filter: #Predicate<TaskItem> { !$0.isDone }, sort: \TaskItem.createdAt) private var openTasks: [TaskItem]
    @Query private var sessions: [FocusSession]
    @FocusState private var rootFocused: Bool
    @AppStorage(PrefKey.longBreakEvery) private var longBreakEvery = 4

    private var todaySeconds: Double {
        sessions.filter { Calendar.current.isDateInToday($0.startedAt) }.reduce(0) { $0 + $1.seconds }
    }

    private var subject: Subject? { subjects.first { $0.id == engine.subjectID } }

    var body: some View {
        @Bindable var engine = engine
        VStack(spacing: 0) {
            HStack {
                Button { router.exitFocus() } label: { Label("Exit focus", systemImage: "arrow.down.right.and.arrow.up.left") }
                    .buttonStyle(.osGhost)
                    .keyboardShortcut(.cancelAction)
                    .help("Exit focus mode (Esc)")
                Spacer()
                PhasePicker()
                Spacer()
                Color.clear.frame(width: 110, height: 1)
            }
            .padding(Space.lg)

            Spacer(minLength: Space.xl)

            ZStack {
                TimerRing(progress: engine.progress, lineWidth: 4, tint: engine.phase == .focus ? Theme.ink : Theme.success)
                    .frame(width: 340, height: 340)
                VStack(spacing: Space.sm) {
                    Text(engine.phase.title.uppercased())
                        .font(Typo.label).tracking(1.2).foregroundStyle(Theme.textTertiary)
                    Text(Fmt.clock(engine.remaining))
                        .font(Typo.displayXL(76))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(Int(engine.remaining / 60)) minutes remaining")
                    Text(engine.state == .paused ? "Paused" : cycleText)
                        .font(Typo.callout).foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(spacing: Space.md) {
                TextField("What are you working on?", text: $engine.taskTitle)
                    .textFieldStyle(.plain)
                    .font(Typo.title)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                HStack(spacing: Space.sm) {
                    Menu {
                        Button("No subject") { engine.subjectID = nil }
                        Divider()
                        ForEach(subjects) { s in Button(s.name) { engine.subjectID = s.id } }
                    } label: {
                        Label(subject?.name ?? "Choose subject", systemImage: subject?.symbol ?? "book.closed")
                    }
                    .menuStyle(.button).buttonStyle(OSButtonStyle(variant: .ghost, compact: true)).fixedSize()

                    let candidates = openTasks.filter { engine.subjectID == nil || $0.subject?.id == engine.subjectID }
                    if !candidates.isEmpty {
                        Menu {
                            ForEach(candidates.prefix(20)) { t in Button(t.title) { engine.taskTitle = t.title } }
                        } label: {
                            Label("Pick a task", systemImage: "checklist")
                        }
                        .menuStyle(.button).buttonStyle(OSButtonStyle(variant: .ghost, compact: true)).fixedSize()
                    }
                }
            }
            .padding(.top, Space.x4)

            HStack(spacing: Space.md) {
                Button { engine.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.osGhost)
                    .disabled(!engine.isActive)
                Button { engine.toggle() } label: {
                    Label(engine.isRunning ? "Pause" : (engine.state == .paused ? "Resume" : "Start"),
                          systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.osPrimary)
                .controlSize(.large)
                Button { engine.skip() } label: { Label("Skip", systemImage: "forward.end") }
                    .buttonStyle(.osGhost)
            }
            .padding(.top, Space.xxl)

            Spacer(minLength: Space.xl)

            Text(todaySeconds > 0 ? "\(Fmt.duration(todaySeconds)) focused today" : "Space to start or pause · Esc to exit")
                .font(Typo.callout)
                .foregroundStyle(Theme.textTertiary)
                .padding(.bottom, Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .focused($rootFocused)
        .onKeyPress(.space) {
            engine.toggle()
            return .handled
        }
        .onAppear { rootFocused = true }
    }

    private var cycleText: String {
        let every = max(1, longBreakEvery)
        let done = engine.completedFocusInCycle % every
        let current = engine.phase == .focus ? done + 1 : (done == 0 ? every : done)
        return "Session \(current) of \(every)"
    }
}

/// Compact timer used by the Pomodoro block and Home.
struct CompactTimer: View {
    @Environment(PomodoroEngine.self) private var engine
    @Environment(AppRouter.self) private var router
    var subjectID: UUID? = nil
    var ringSize: CGFloat = 120

    private var ownsTimer: Bool { subjectID == nil || engine.subjectID == subjectID || !engine.isActive }

    var body: some View {
        HStack(spacing: Space.xl) {
            ZStack {
                TimerRing(progress: engine.progress, lineWidth: 3, tint: engine.phase == .focus ? Theme.ink : Theme.success)
                VStack(spacing: 2) {
                    Text(Fmt.clock(engine.remaining)).font(Typo.numeral)
                    Text(engine.phase.title).font(Typo.callout).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: ringSize, height: ringSize)

            VStack(alignment: .leading, spacing: Space.md) {
                PhasePicker()
                HStack(spacing: Space.sm) {
                    Button {
                        if let subjectID, !engine.isActive { engine.subjectID = subjectID }
                        engine.toggle()
                    } label: {
                        Label(engine.isRunning ? "Pause" : (engine.state == .paused ? "Resume" : "Start"),
                              systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.osPrimary)
                    Button { engine.reset() } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.osSecondary)
                        .disabled(!engine.isActive)
                        .help("Reset")
                    Button { withAnimation(Motion.sidebar) { router.selection = .focus } } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.osSecondary)
                    .help("Open Focus mode")
                }
                if !ownsTimer {
                    Text("The timer is running for another subject.").font(Typo.callout).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}
