//
//  UISnapshotHarness.swift
//  open-study
//
//  DEBUG-only visual verification. Launch with `-uiSnapshots` to run against
//  an in-memory store (real data is never touched), seed fixture content,
//  visit each screen and write window snapshots to the app's tmp directory.
//

#if DEBUG
import SwiftUI
import SwiftData
import AppKit

enum UISnapshotHarness {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-uiSnapshots") }
    static var seedEnabled: Bool { !ProcessInfo.processInfo.arguments.contains("-uiSnapshotsEmpty") }

    static func seed(_ context: ModelContext) {
        guard seedEnabled else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let physics = Subject(name: "Physics", symbol: "atom", colorKey: "sky", sortIndex: 0)
        let chem = Subject(name: "Chemistry", symbol: "flask", colorKey: "sage", sortIndex: 1)
        let history = Subject(name: "History", symbol: "building.columns", colorKey: "clay", sortIndex: 2)
        [physics, chem, history].forEach(context.insert)

        func block(_ kind: BlockKind, _ i: Int, _ s: Subject) -> Block {
            let b = Block(kind: kind, sortIndex: i); context.insert(b); b.subject = s; return b
        }
        let h = block(.heading, 0, physics); h.text = "Thermodynamics"; h.level = 1
        let t = block(.text, 1, physics)
        t.text = "The first law states that energy is conserved. Heat added to a system equals the change in internal energy plus the work done by the system."
        t.richData = NoteCodec.make(plain: t.text)
        let c = block(.callout, 2, physics); c.text = "Exam tip: always state your sign convention for work."; c.tone = .yellow
        let deck = Deck(name: "Thermo definitions"); context.insert(deck); deck.subject = physics
        for (f, b) in [("Entropy", "A measure of disorder"), ("Enthalpy", "H = U + pV"), ("Adiabatic", "No heat exchange")] {
            let card = Flashcard(front: f, back: b); context.insert(card); card.deck = deck
        }
        let fb = block(.flashcards, 3, physics); fb.deck = deck; fb.widthFraction = 0.5
        let pb = block(.pomodoro, 4, physics); pb.widthFraction = 0.5
        let tb = block(.tasks, 5, physics)
        for (title, due, p) in [("Problem set 4", 0, TaskPriority.high), ("Read chapter 7", 2, .medium)] {
            let task = TaskItem(title: title, subject: physics, dueDate: cal.date(byAdding: .day, value: due, to: today), priority: p)
            context.insert(task); task.block = tb
        }
        let cl = block(.checklist, 6, physics); cl.title = "Revision"; cl.checklist = [ChecklistEntry(text: "Formula sheet", done: true), ChecklistEntry(text: "Past paper 2023")]
        cl.widthFraction = 0.5
        let sb = block(.statistics, 7, physics); sb.widthFraction = 0.5

        let task = TaskItem(title: "Titration lab report", subject: chem, dueDate: cal.date(byAdding: .day, value: -1, to: today), priority: .high)
        context.insert(task)
        let exam = StudyEvent(title: "Physics Paper 1", kind: .exam, start: cal.date(byAdding: .day, value: 12, to: today)!.addingTimeInterval(9 * 3600),
                              end: cal.date(byAdding: .day, value: 12, to: today)!.addingTimeInterval(11 * 3600), subject: physics)
        context.insert(exam)
        let study = StudyEvent(title: "Organic revision", kind: .study, start: today.addingTimeInterval(15 * 3600), end: today.addingTimeInterval(16 * 3600), subject: chem)
        context.insert(study)
        for d in 0..<9 {
            let start = cal.date(byAdding: .day, value: -d, to: today)!.addingTimeInterval(10 * 3600)
            let s = FocusSession(startedAt: start, endedAt: start.addingTimeInterval(1500), seconds: Double(1500 + (d % 3) * 600), completed: true,
                                 subject: d % 2 == 0 ? physics : chem, taskTitle: "")
            context.insert(s)
        }
        let habit = Habit(name: "Review flashcards", symbol: "rectangle.on.rectangle.angled", sortIndex: 0)
        context.insert(habit)
        for d in 1..<5 { let ch = HabitCheck(day: cal.date(byAdding: .day, value: -d, to: today)!); context.insert(ch); ch.habit = habit }
        try? context.save()
    }

    @MainActor
    static func run(router: AppRouter, subjectID: () -> UUID?) async {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(1.5))
        var shots: [(String, SidebarItem)] = [("home", .home), ("calendar", .calendar), ("tasks", .tasks), ("flashcards", .flashcards),
                                              ("statistics", .statistics), ("settings", .settings)]
        if let id = subjectID() { shots.insert(("subject", .subject(id)), at: 1) }
        shots.append(("focus", .focus))
        for (name, item) in shots {
            router.selection = item
            try? await Task.sleep(for: .seconds(1.2))
            capture(to: dir.appendingPathComponent("\(name).png"))
        }
        if let container = container, let deck = try? container.mainContext.fetch(FetchDescriptor<Deck>()).first {
            for dark in [true, false] {
                captureStandalone(CardEditor(deck: deck, card: nil).modelContainer(container), dark: dark,
                                  to: dir.appendingPathComponent("sheet-addcard-\(dark ? "dark" : "light").png"))
            }
        }
        router.selection = .home
        router.sidebarVisible = false
        try? await Task.sleep(for: .seconds(1))
        capture(to: dir.appendingPathComponent("home-nosidebar.png"))
        router.sidebarVisible = true
        print("SNAPSHOTS_DONE \(dir.path)")
        if ProcessInfo.processInfo.arguments.contains("-uiSnapshotsQuit") { NSApp.terminate(nil) }
    }

    @MainActor
    static func dump(_ v: NSView, depth: Int) {
        guard depth < 14 else { return }
        var extra = ""
        if let s = v as? NSScrollView {
            extra = " drawsBG=\(s.drawsBackground) doc=\(s.documentView.map { "\($0.frame)" } ?? "nil")"
        }
        print("VIEWDUMP " + String(repeating: "  ", count: depth) + "\(type(of: v)) \(v.frame) hidden=\(v.isHidden) alpha=\(v.alphaValue)\(extra)")
        for sub in v.subviews { dump(sub, depth: depth + 1) }
    }

    static var container: ModelContainer?

    /// Renders a view (e.g. a sheet's content) in an off-screen window.
    @MainActor
    static func captureStandalone<V: View>(_ view: V, dark: Bool, to url: URL) {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        write(host, to: url)
    }

    @MainActor
    static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title == "Open Study" }) ?? NSApp.mainWindow,
              let view = window.contentView?.superview ?? window.contentView else { return }
        window.appearance = NSAppearance(named: ProcessInfo.processInfo.arguments.contains("-uiSnapshotsDark") ? .darkAqua : .aqua)
        write(view, to: url)
        // The workspace's scroll content isn't included in a window-level cache, so capture it separately.
        if let scroll = scrollViews(in: view).filter({ $0.frame.width > 400 }).max(by: { $0.frame.width < $1.frame.width }),
           let doc = scroll.documentView {
            write(doc, to: url.deletingPathExtension().appendingPathExtension("doc.png"))
        }
    }

    @MainActor
    private static func scrollViews(in v: NSView) -> [NSScrollView] {
        (v as? NSScrollView).map { [$0] } ?? v.subviews.flatMap(scrollViews)
    }

    @MainActor
    private static func write(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        (view.window?.appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
