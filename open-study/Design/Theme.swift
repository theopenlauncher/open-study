//
//  Theme.swift
//  open-study
//
//  Design tokens. See DESIGN.md §2, §3, §9. This is the only file that
//  contains raw hex values, font sizes and spacing constants.
//

import SwiftUI
import AppKit

// MARK: - Colour helpers

nonisolated func hexColor(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

nonisolated func dynamicNSColor(light: UInt32, dark: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return hexColor(isDark ? dark : light)
    }
}

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: dynamicNSColor(light: light, dark: dark))
    }
}

// MARK: - Palette (DESIGN.md §2)

enum Theme {
    // Neutrals
    static let canvas = Color.dynamic(light: 0xF6F4F0, dark: 0x1C1B19)
    static let surface = Color.dynamic(light: 0xFDFCFA, dark: 0x232220)
    static let raised = Color.dynamic(light: 0xFFFFFF, dark: 0x2A2926)
    static let muted = Color.dynamic(light: 0xF2EFE8, dark: 0x2D2B28)
    static let sidebarHover = Color.dynamic(light: 0xEFECE5, dark: 0x262522)
    static let sidebarActive = Color.dynamic(light: 0xE9E5DC, dark: 0x2F2D2A)
    static let hover = Color.dynamic(light: 0xF4F2ED, dark: 0x2B2A27)
    static let border = Color.dynamic(light: 0xE9E5DD, dark: 0x34322F)
    static let borderStrong = Color.dynamic(light: 0xD9D3C8, dark: 0x45423E)

    // Text
    static let textPrimary = Color.dynamic(light: 0x1E1C19, dark: 0xEDEBE6)
    static let textSecondary = Color.dynamic(light: 0x6A655C, dark: 0xA9A39A)
    static let textTertiary = Color.dynamic(light: 0x9A948A, dark: 0x77726A)
    /// Labels on disabled controls: clearly inactive but still readable (≥ 3:1).
    static let textDisabled = Color.dynamic(light: 0x8C867C, dark: 0x8F8A82)
    /// Placeholder text in fields: readable, but clearly not entered text.
    static let placeholder = Color.dynamic(light: 0xA49E94, dark: 0x85807A)
    /// Text field borders — one step stronger than `border` so inputs read on every surface.
    static let inputBorder = Color.dynamic(light: 0xE0DBD1, dark: 0x4A4743)

    // Ink & accent
    static let ink = Color.dynamic(light: 0x1E1C19, dark: 0xEDEBE6)
    static let onInk = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1B19)
    static let accent = Color.dynamic(light: 0x4A5BD0, dark: 0x8592F0)
    static let accentSoft = Color.dynamic(light: 0xECEEFB, dark: 0x2B2F4A)

    // Semantic
    static let success = Color.dynamic(light: 0x3E8A5A, dark: 0x6CC08A)
    static let warning = Color.dynamic(light: 0xB7791F, dark: 0xE0A957)
    static let danger = Color.dynamic(light: 0xC0443B, dark: 0xE57A70)
    static let badgeBg = Color.dynamic(light: 0xFCE6BF, dark: 0x4A3A1E)
    static let badgeText = Color.dynamic(light: 0x7A4F12, dark: 0xF2C987)

    // AppKit equivalents used by the rich text editor
    static let nsTextPrimary = dynamicNSColor(light: 0x1E1C19, dark: 0xEDEBE6)
    static let nsTextTertiary = dynamicNSColor(light: 0x9A948A, dark: 0x77726A)
    static let nsMuted = dynamicNSColor(light: 0xF2EFE8, dark: 0x2D2B28)
    static let nsAccent = dynamicNSColor(light: 0x4A5BD0, dark: 0x8592F0)
}

// MARK: - Subject colours (DESIGN.md §2.5)

enum SubjectColor: String, CaseIterable, Identifiable {
    case clay, sage, sky, teal, lavender, rose, sand, slate
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .clay: Color(nsColor: hexColor(0xC2774F))
        case .sage: Color(nsColor: hexColor(0x6B9871))
        case .sky: Color(nsColor: hexColor(0x5A8BBB))
        case .teal: Color(nsColor: hexColor(0x4C9693))
        case .lavender: Color(nsColor: hexColor(0x8A7BC2))
        case .rose: Color(nsColor: hexColor(0xC26A84))
        case .sand: Color(nsColor: hexColor(0xB0954F))
        case .slate: Color(nsColor: hexColor(0x6E7A87))
        }
    }

    var name: String { rawValue.capitalized }

    static func from(_ key: String) -> SubjectColor { SubjectColor(rawValue: key) ?? .slate }
}

// MARK: - Typography (DESIGN.md §3)

enum Typo {
    static func displayXL(_ size: CGFloat = 64) -> Font { .system(size: size, weight: .light, design: .serif).monospacedDigit() }
    static let display = Font.system(size: 32, weight: .regular, design: .serif)
    static let numeral = Font.system(size: 28, weight: .regular, design: .serif).monospacedDigit()
    static let numeralSmall = Font.system(size: 22, weight: .regular, design: .serif).monospacedDigit()
    static let title = Font.system(size: 17, weight: .semibold)
    static let headline = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let reading = Font.system(size: 15)
    static let h1 = Font.system(size: 26, weight: .semibold)
    static let h2 = Font.system(size: 20, weight: .semibold)
    static let h3 = Font.system(size: 16, weight: .semibold)
    static let callout = Font.system(size: 12)
    static let label = Font.system(size: 11, weight: .semibold)
    static let mono = Font.system(size: 13, design: .monospaced)
    static let nav = Font.system(size: 13.5)
}

// MARK: - Spacing & radii (DESIGN.md §9)

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s6: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let x3: CGFloat = 32
    static let x4: CGFloat = 40
    static let x5: CGFloat = 48
}

enum Radius {
    static let window: CGFloat = 12
    static let card: CGFloat = 10
    static let control: CGFloat = 8
    static let icon: CGFloat = 7
    static let chip: CGFloat = 5
}

enum Layout {
    static let sidebarWidth: CGFloat = 232
    static let topStrip: CGFloat = 30
    static let readingWidth: CGFloat = 880
    static let dashboardWidth: CGFloat = 1120
    static let blockGutter: CGFloat = 44
}

enum Motion {
    static let hover = Animation.easeOut(duration: 0.12)
    static let fade = Animation.easeOut(duration: 0.18)
    static let sidebar = Animation.easeOut(duration: 0.25)
    static let flip = Animation.spring(response: 0.4, dampingFraction: 0.85)
}
