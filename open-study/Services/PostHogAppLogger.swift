//
//  PostHogAppLogger.swift
//  open-study
//

import PostHog

enum PostHogAppLogger {
    /// Nil when the user has turned off usage data, so no log records are sent.
    private static var logger: PostHogLogger? {
        Analytics.isEnabled ? PostHogSDK.shared.logger : nil
    }

    static func appStarted() {
        logger?.info(
            "app_started",
            attributes: ["app_runtime": "macos"]
        )
    }

    static func studyStoreInitialized() {
        logger?.info("study_store_initialized")
    }

    static func studyStoreInitializationFailed() {
        logger?.error("study_store_initialization_failed")
    }

    static func focusSessionSaved(durationSeconds: Int, completed: Bool, hasSubject: Bool) {
        logger?.info(
            "focus_session_saved",
            attributes: [
                "duration_seconds": durationSeconds,
                "completed": completed,
                "has_subject": hasSubject,
            ]
        )
    }
}
