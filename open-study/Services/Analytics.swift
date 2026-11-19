//
//  Analytics.swift
//  open-study
//

import Foundation
import PostHog

/// The user's "Share anonymous usage data" setting is the source of truth for PostHog consent.
enum Analytics {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.analyticsEnabled)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }

    /// Brings the SDK's own saved opt-out state in line with the setting after `setup()`.
    static func syncWithPreference() {
        if isEnabled == PostHogSDK.shared.isOptOut() {
            setEnabled(isEnabled)
        }
    }
}
