//
//  PostHogAppLogger.swift
//  open-study
//

import PostHog

enum PostHogAppLogger {
    static func appStarted() {
        PostHogSDK.shared.logger?.info(
            "app_started",
            attributes: ["app_runtime": "macos"]
        )
    }

    static func studyStoreInitialized() {
        PostHogSDK.shared.logger?.info("study_store_initialized")
    }

    static func studyStoreInitializationFailed() {
        PostHogSDK.shared.logger?.error("study_store_initialization_failed")
    }

    static func focusSessionSaved(durationSeconds: Int, completed: Bool, hasSubject: Bool) {
        PostHogSDK.shared.logger?.info(
            "focus_session_saved",
            attributes: [
                "duration_seconds": durationSeconds,
                "completed": completed,
                "has_subject": hasSubject,
            ]
        )
    }
}
