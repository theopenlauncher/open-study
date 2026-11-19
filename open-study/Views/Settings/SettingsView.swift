//
//  SettingsView.swift
//  open-study
//

import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    var isWindow = false
    @Environment(PomodoroEngine.self) private var engine
    @Query private var documents: [StudyDocument]

    @AppStorage(PrefKey.focusMinutes) private var focusMinutes = 25
    @AppStorage(PrefKey.shortBreakMinutes) private var shortBreak = 5
    @AppStorage(PrefKey.longBreakMinutes) private var longBreak = 15
    @AppStorage(PrefKey.longBreakEvery) private var longEvery = 4
    @AppStorage(PrefKey.autoStartBreaks) private var autoBreaks = true
    @AppStorage(PrefKey.autoStartFocus) private var autoFocus = false
    @AppStorage(PrefKey.playSound) private var playSound = true
    @AppStorage(PrefKey.notificationsEnabled) private var notifications = true
    @AppStorage(PrefKey.dailyGoalMinutes) private var dailyGoal = 120
    @AppStorage(PrefKey.appearance) private var appearance = "system"
    @AppStorage(PrefKey.analyticsEnabled) private var analyticsEnabled = true
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Group {
            if isWindow {
                form.frame(width: 520, height: 600)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: "Settings", subtitle: "Preferences are stored on this Mac.")
                        .padding(.horizontal, Space.x5)
                        .padding(.top, 36)
                        .padding(.bottom, Space.sm)
                    form.frame(maxWidth: 720, alignment: .leading)
                        .padding(.horizontal, Space.x4 - 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task { await refreshAuth() }
        .onChange(of: focusMinutes) { engine.resetDurations() }
        .onChange(of: shortBreak) { engine.resetDurations() }
        .onChange(of: longBreak) { engine.resetDurations() }
    }

    private var form: some View {
        Form {
            Section("Focus timer") {
                Stepper("Focus: \(focusMinutes) min", value: $focusMinutes, in: 5...120, step: 5)
                Stepper("Short break: \(shortBreak) min", value: $shortBreak, in: 1...30)
                Stepper("Long break: \(longBreak) min", value: $longBreak, in: 5...60, step: 5)
                Stepper("Long break after \(longEvery) focus sessions", value: $longEvery, in: 2...8)
                Toggle("Start breaks automatically", isOn: $autoBreaks)
                Toggle("Start next focus session automatically", isOn: $autoFocus)
                if engine.isActive {
                    Text("New durations apply when the current session ends or is reset.")
                        .font(Typo.callout).foregroundStyle(Theme.textTertiary)
                }
            }
            Section("Notifications") {
                Toggle("Notify when a session ends", isOn: $notifications)
                    .onChange(of: notifications) { _, on in if on { NotificationDelegate.requestAuthorization(); Task { await refreshAuth() } } }
                Toggle("Play a sound", isOn: $playSound)
                if notifications && authStatus == .denied {
                    HStack {
                        Text("Notifications are turned off for Open Study in System Settings.")
                            .font(Typo.callout).foregroundStyle(Theme.warning)
                        Spacer()
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                } else if notifications && authStatus == .notDetermined {
                    Button("Allow Notifications…") {
                        NotificationDelegate.requestAuthorization()
                        Task { try? await Task.sleep(for: .seconds(1)); await refreshAuth() }
                    }
                }
            }
            Section("Study goal") {
                Stepper("Daily focus goal: \(dailyGoal) min", value: $dailyGoal, in: 15...600, step: 15)
            }
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            Section("Data") {
                LabeledContent("Storage", value: "On this Mac only — no account or internet needed")
                LabeledContent("Imported PDFs", value: "\(documents.count)")
                Button("Show Data Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDirectory])
                }
            }
            Section("Privacy") {
                Toggle("Share anonymous usage data", isOn: $analyticsEnabled)
                    .onChange(of: analyticsEnabled) { _, on in Analytics.setEnabled(on) }
                Text("Sends counts and on/off details (for example, \"a task was completed\") and crash reports to help improve Open Study. Your notes, card text, task titles and files never leave this Mac.")
                    .font(Typo.callout).foregroundStyle(Theme.textTertiary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func refreshAuth() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
    }
}
