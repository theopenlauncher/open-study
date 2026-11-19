//
//  Analytics.swift
//  open-study
//

import Foundation
import PostHog

/// The user's "Share anonymous usage data" setting is the source of truth for PostHog consent.
/// When it is off, the SDK is never started (or is shut down), so the app makes no requests to
/// PostHog at all — not even the config and feature-flag checks the SDK makes while opted out.
@MainActor
enum Analytics {
    private static var isRunning = false

    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.analyticsEnabled)
    }

    /// Call once at launch, after `PrefKey.registerDefaults()`.
    static func start() {
        guard isEnabled else { return }
        setUp()
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            setUp()
        } else if isRunning {
            PostHogSDK.shared.optOut()
            PostHogSDK.shared.close()
            isRunning = false
        }
    }

    private static func setUp() {
        guard !isRunning else { return }
        let env = ProcessInfo.processInfo.environment
        let projectToken = env["POSTHOG_PROJECT_TOKEN"] ?? "phc_wMBzHUbz4gcZhf5qPrXHdFXFNG6hmXy6csrwUZEHEB39"
        let host = env["POSTHOG_HOST"] ?? "https://us.i.posthog.com"
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.errorTrackingConfig.autoCapture = true
        config.logs.serviceName = "open-study"
        #if DEBUG
        config.logs.environment = "development"
        #else
        config.logs.environment = "production"
        #endif
        PostHogSDK.shared.setup(config)
        // A previous opt-out saved by the SDK would otherwise outrank the user's current choice.
        if PostHogSDK.shared.isOptOut() {
            PostHogSDK.shared.optIn()
        }
        isRunning = true
    }
}
