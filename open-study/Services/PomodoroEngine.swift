//
//  PomodoroEngine.swift
//  open-study
//
//  A single app-wide timer. It is time-stamp based (end date), so it stays
//  correct while the user navigates, the window is hidden or App Nap delays
//  ticks. Completed and partial focus sessions are logged to SwiftData.
//

import Foundation
import SwiftData
import AppKit
import UserNotifications
import Observation
import PostHog

enum PomodoroPhase: String, CaseIterable, Identifiable {
    case focus, shortBreak, longBreak
    var id: String { rawValue }
    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }
}

enum PrefKey {
    static let focusMinutes = "focusMinutes"
    static let shortBreakMinutes = "shortBreakMinutes"
    static let longBreakMinutes = "longBreakMinutes"
    static let longBreakEvery = "longBreakEvery"
    static let autoStartBreaks = "autoStartBreaks"
    static let autoStartFocus = "autoStartFocus"
    static let playSound = "playSound"
    static let notificationsEnabled = "notificationsEnabled"
    static let dailyGoalMinutes = "dailyGoalMinutes"
    static let appearance = "appearance"
    static let sidebarVisible = "sidebarVisible"
    static let analyticsEnabled = "analyticsEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, longBreakEvery: 4,
            autoStartBreaks: true, autoStartFocus: false, playSound: true, notificationsEnabled: true,
            dailyGoalMinutes: 120, appearance: "system", sidebarVisible: true,
            analyticsEnabled: true,
        ])
    }
}

@MainActor
@Observable
final class PomodoroEngine {
    enum RunState { case idle, running, paused }

    private(set) var phase: PomodoroPhase = .focus
    private(set) var state: RunState = .idle
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var phaseDuration: TimeInterval = 25 * 60
    private(set) var completedFocusInCycle = 0
    /// Increments whenever a session is logged so views can refresh.
    private(set) var lastLoggedAt: Date?

    var subjectID: UUID?
    var taskTitle: String = ""

    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var focusStartedAt: Date?
    @ObservationIgnored private var focusElapsedBeforePause: TimeInterval = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private let notificationID = "pomodoro.phase.end"

    init() {
        PrefKey.registerDefaults()
        resetDurations()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.logPartialIfNeeded() }
        }
    }

    // MARK: Settings

    private var defaults: UserDefaults { .standard }

    func duration(for phase: PomodoroPhase) -> TimeInterval {
        let minutes: Int
        switch phase {
        case .focus: minutes = defaults.integer(forKey: PrefKey.focusMinutes)
        case .shortBreak: minutes = defaults.integer(forKey: PrefKey.shortBreakMinutes)
        case .longBreak: minutes = defaults.integer(forKey: PrefKey.longBreakMinutes)
        }
        return TimeInterval(max(1, minutes) * 60)
    }

    /// Applies changed durations when the timer is not running.
    func resetDurations() {
        guard state == .idle else { return }
        phaseDuration = duration(for: phase)
        remaining = phaseDuration
    }

    var progress: Double { phaseDuration > 0 ? 1 - remaining / phaseDuration : 0 }
    var isRunning: Bool { state == .running }
    var isActive: Bool { state != .idle }

    // MARK: Controls

    func start() {
        guard state != .running else { return }
        if state == .idle {
            phaseDuration = duration(for: phase)
            remaining = phaseDuration
            focusElapsedBeforePause = 0
            if phase == .focus { focusStartedAt = Date() }
        }
        endDate = Date().addingTimeInterval(remaining)
        state = .running
        startTicking()
        scheduleNotification()
        beginActivity()
    }

    func pause() {
        guard state == .running, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if phase == .focus { focusElapsedBeforePause = phaseDuration - remaining }
        state = .paused
        stopTicking()
        cancelNotification()
        endActivity()
    }

    func toggle() { state == .running ? pause() : start() }

    func reset() {
        logPartialIfNeeded()
        stopTicking()
        cancelNotification()
        endActivity()
        state = .idle
        endDate = nil
        resetDurations()
    }

    func skip() {
        logPartialIfNeeded()
        stopTicking()
        cancelNotification()
        endActivity()
        advance(afterCompleting: false)
    }

    func select(_ newPhase: PomodoroPhase) {
        guard newPhase != phase || state != .idle else { return }
        reset()
        phase = newPhase
        resetDurations()
    }

    // MARK: Ticking

    private func startTicking() {
        stopTicking()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .running, let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            complete()
        } else {
            remaining = left
        }
    }

    private func complete() {
        stopTicking()
        endActivity()
        if phase == .focus {
            logSession(seconds: phaseDuration, completed: true)
            completedFocusInCycle += 1
        }
        if defaults.bool(forKey: PrefKey.playSound) { NSSound(named: "Glass")?.play() }
        advance(afterCompleting: true)
    }

    private func advance(afterCompleting: Bool) {
        let finished = phase
        state = .idle
        endDate = nil
        focusStartedAt = nil
        focusElapsedBeforePause = 0
        if finished == .focus {
            let every = max(1, defaults.integer(forKey: PrefKey.longBreakEvery))
            phase = (completedFocusInCycle > 0 && completedFocusInCycle % every == 0 && afterCompleting) ? .longBreak : .shortBreak
        } else {
            phase = .focus
        }
        resetDurations()
        guard afterCompleting else { return }
        let auto = phase == .focus ? defaults.bool(forKey: PrefKey.autoStartFocus) : defaults.bool(forKey: PrefKey.autoStartBreaks)
        if auto { start() }
    }

    // MARK: Logging

    private var elapsedFocus: TimeInterval {
        guard phase == .focus else { return 0 }
        switch state {
        case .running: return phaseDuration - max(0, endDate?.timeIntervalSinceNow ?? remaining)
        case .paused: return focusElapsedBeforePause
        case .idle: return 0
        }
    }

    /// Focus time of at least one minute is recorded even when a session is cut short.
    private func logPartialIfNeeded() {
        let elapsed = elapsedFocus
        if phase == .focus && state != .idle && elapsed >= 60 {
            logSession(seconds: elapsed, completed: false)
        }
    }

    private func logSession(seconds: TimeInterval, completed: Bool) {
        guard let modelContext else { return }
        var subject: Subject?
        if let subjectID {
            let descriptor = FetchDescriptor<Subject>(predicate: #Predicate { $0.id == subjectID })
            subject = try? modelContext.fetch(descriptor).first
        }
        let start = focusStartedAt ?? Date().addingTimeInterval(-seconds)
        let session = FocusSession(startedAt: start, endedAt: Date(), seconds: seconds, completed: completed,
                                   subject: subject, taskTitle: taskTitle)
        modelContext.insert(session)
        do {
            try modelContext.save()
            let durationSeconds = Int(seconds.rounded())
            PostHogSDK.shared.capture("focus_session_logged", properties: [
                "duration_seconds": durationSeconds,
                "completed": completed,
                "has_subject": subject != nil,
            ])
            PostHogAppLogger.focusSessionSaved(
                durationSeconds: durationSeconds,
                completed: completed,
                hasSubject: subject != nil
            )
        } catch {}
        lastLoggedAt = Date()
    }

    // MARK: Notifications & App Nap

    private func scheduleNotification() {
        guard defaults.bool(forKey: PrefKey.notificationsEnabled), let endDate else { return }
        let content = UNMutableNotificationContent()
        content.title = phase == .focus ? "Focus session complete" : "Break is over"
        content.body = phase == .focus ? "Nice work. Time for a break." : "Ready for the next focus session?"
        // The in-app chime (NSSound) plays on completion, so the banner stays silent to avoid a double sound.
        let interval = max(1, endDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                         reason: "Pomodoro timer running")
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}

/// Shows notification banners even while the app is frontmost.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
