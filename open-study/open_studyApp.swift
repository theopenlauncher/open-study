//
//  open_studyApp.swift
//  open-study
//
//  Created by Harshil on 2026-11-18.
//

import SwiftUI
import SwiftData
import UserNotifications
import PostHog

@main
struct open_studyApp: App {
    @State private var router = AppRouter()
    @State private var engine = PomodoroEngine()
    private let container: Result<ModelContainer, Error>

    init() {
        PrefKey.registerDefaults()
        Analytics.start()
        PostHogAppLogger.appStarted()

        do {
            let schema = Schema(AppSchema.models)
            var config = ModelConfiguration(schema: schema, url: AppPaths.storeURL, cloudKitDatabase: .none)
            #if DEBUG
            if UISnapshotHarness.isEnabled {
                config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            }
            #endif
            container = .success(try ModelContainer(for: schema, configurations: config))
            PostHogAppLogger.studyStoreInitialized()
        } catch {
            container = .failure(error)
            PostHogAppLogger.studyStoreInitializationFailed()
        }
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup("Open Study", id: "main") {
            Group {
                switch container {
                case .success(let container):
                    ContentView()
                        .modelContainer(container)
                case .failure(let error):
                    StorageErrorView(error: error)
                }
            }
            .environment(router)
            .environment(engine)
            .appearancePreference()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .commands { AppCommands(router: router, engine: engine) }

        WindowGroup("Document", id: "pdf", for: UUID.self) { $documentID in
            if case .success(let container) = container, let documentID {
                PDFReaderWindow(documentID: documentID)
                    .modelContainer(container)
                    .appearancePreference()
            }
        }
        .defaultSize(width: 900, height: 1000)

        Settings {
            if case .success(let container) = container {
                SettingsView(isWindow: true)
                    .modelContainer(container)
                    .environment(engine)
                    .appearancePreference()
            }
        }
    }
}

private struct AppearanceModifier: ViewModifier {
    @AppStorage(PrefKey.appearance) private var appearance = "system"
    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
    }
}

extension View {
    func appearancePreference() -> some View { modifier(AppearanceModifier()) }
}

struct AppCommands: Commands {
    let router: AppRouter
    let engine: PomodoroEngine

    var body: some Commands {
        TextFormattingCommands()

        CommandGroup(after: .newItem) {
            Button("New Subject") {
                router.sidebarVisible = true
                router.showNewSubject = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(before: .toolbar) {
            Button(router.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                withAnimation(Motion.sidebar) { router.sidebarVisible.toggle() }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
        }

        CommandMenu("Go") {
            ForEach(Array(SidebarItem.global.enumerated()), id: \.offset) { index, item in
                Button(item.title) { router.selection = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }

        CommandMenu("Timer") {
            Button(engine.isRunning ? "Pause Timer" : "Start Timer") { engine.toggle() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Reset Timer") { engine.reset() }
                .disabled(!engine.isActive)
            Button("Skip to Next Phase") { engine.skip() }
            Divider()
            Button(router.isFocusMode ? "Exit Focus Mode" : "Enter Focus Mode") {
                if router.isFocusMode { router.exitFocus() } else {
                    withAnimation(Motion.sidebar) { router.selection = .focus }
                }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
    }
}

struct StorageErrorView: View {
    let error: Error
    var body: some View {
        VStack(spacing: Space.lg) {
            EmptyStateView(
                symbol: "externaldrive.badge.exclamationmark",
                title: "Open Study couldn't open its data",
                message: "Your data hasn't been deleted. The store may be from a newer version or damaged.\n\n\(error.localizedDescription)"
            )
            Button("Reveal Data Folder") {
                NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory])
            }
            .buttonStyle(.osSecondary)
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Theme.surface)
    }
}
