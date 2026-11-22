//
//  Components.swift
//  open-study
//
//  Reusable building blocks. See DESIGN.md §7, §8, §12, §14.
//

import SwiftUI
import AppKit

// MARK: - Buttons

enum OSButtonVariant { case primary, secondary, ghost, destructive }

struct OSButtonStyle: ButtonStyle {
    var variant: OSButtonVariant = .secondary
    var compact: Bool = false
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        OSButtonBody(configuration: configuration, variant: variant, compact: compact, fullWidth: fullWidth)
    }
}

private struct OSButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: OSButtonVariant
    let compact: Bool
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(Typo.headline)
            .labelStyle(OSLabelStyle())
            .lineLimit(1)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(height: compact ? 26 : 30)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay {
                if let stroke {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(stroke, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .onHover { hovering = $0 && isEnabled }
            .animation(Motion.hover, value: hovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(Motion.fade, value: isEnabled)
    }

    // Disabled buttons use explicit, readable colours rather than fading the
    // whole button, which made labels illegible in dark mode (DESIGN.md §7).

    private var foreground: Color {
        guard isEnabled else { return Theme.textDisabled }
        switch variant {
        case .primary: return Theme.onInk
        case .secondary: return Theme.textPrimary
        case .ghost: return hovering ? Theme.textPrimary : Theme.textSecondary
        case .destructive: return Theme.danger
        }
    }

    private var background: Color {
        switch variant {
        case .primary: return isEnabled ? Theme.ink.opacity(hovering ? 0.88 : 1) : Theme.muted
        case .secondary: return isEnabled && hovering ? Theme.hover : Theme.raised
        case .ghost: return isEnabled && hovering ? Theme.hover : .clear
        case .destructive: return isEnabled && hovering ? Theme.danger.opacity(0.08) : .clear
        }
    }

    private var stroke: Color? {
        switch variant {
        case .primary: return isEnabled ? nil : Theme.border
        case .secondary: return Theme.border
        case .destructive: return isEnabled ? Theme.danger.opacity(0.3) : Theme.border
        case .ghost: return nil
        }
    }
}

struct OSLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 12, weight: .medium))
            configuration.title
        }
    }
}

extension ButtonStyle where Self == OSButtonStyle {
    static var osPrimary: OSButtonStyle { OSButtonStyle(variant: .primary) }
    static var osSecondary: OSButtonStyle { OSButtonStyle(variant: .secondary) }
    static var osGhost: OSButtonStyle { OSButtonStyle(variant: .ghost) }
    static var osDestructive: OSButtonStyle { OSButtonStyle(variant: .destructive) }
}

/// 28pt square icon button with hover fill and tooltip.
struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 28
    var onCanvas = false
    var tint: Color = Theme.textSecondary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(hovering ? Theme.textPrimary : tint)
                .frame(width: size, height: size)
                .background(hovering ? (onCanvas ? Theme.sidebarHover : Theme.hover) : .clear,
                            in: RoundedRectangle(cornerRadius: Radius.icon, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Menu that looks like a ghost button (native NSMenu underneath).
struct GhostMenu<Content: View>: View {
    let title: String
    var symbol: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
                Text(title).font(Typo.bodyMedium)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.osGhost)
        .fixedSize()
    }
}

// MARK: - Containers

struct OSCard<Content: View>: View {
    var padding: CGFloat = Space.lg
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
    }
}

extension View {
    func cardStyle(padding: CGFloat = Space.lg) -> some View {
        self.padding(padding)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
    }

    func floatShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 6)
    }

    func hoverHighlight(cornerRadius: CGFloat = Radius.control, onCanvas: Bool = false) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius, onCanvas: onCanvas))
    }
}

struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat
    var onCanvas: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? (onCanvas ? Theme.sidebarHover : Theme.hover) : .clear,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
    }
}

struct StatTile: View {
    let value: String
    let unit: String
    var caption: String? = nil
    var symbol: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(Typo.numeral).foregroundStyle(Theme.textPrimary)
                Text(unit).font(Typo.body).foregroundStyle(Theme.textSecondary)
            }
            if let caption {
                Text(caption).font(Typo.callout).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct SectionLabel<Trailing: View>: View {
    let text: String
    var trailing: () -> Trailing

    init(_ text: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(Typo.label)
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            trailing()
        }
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ text: String) {
        self.text = text
        self.trailing = { EmptyView() }
    }
}

// MARK: - Page frame (DESIGN.md §5)

struct PageHeader<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Typo.display).foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle).font(Typo.body).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Space.lg)
            accessory()
        }
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = { EmptyView() }
    }
}

/// Scrollable page with the standard gutters and max width.
struct PageScroll<Content: View>: View {
    var maxWidth: CGFloat = Layout.dashboardWidth
    var centered = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .frame(maxWidth: maxWidth, alignment: .leading)
                .padding(.horizontal, geo.size.width < 900 ? Space.x3 : Space.x5)
                .padding(.top, 36)
                .padding(.bottom, Space.x5)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            }
            .scrollIndicators(.automatic)
        }
    }
}

// MARK: - Empty state (DESIGN.md §12)

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var actionSymbol: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 48, height: 48)
                .background(Theme.muted, in: Circle())
            Text(title).font(Typo.title).foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Typo.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    if let actionSymbol { Label(actionTitle, systemImage: actionSymbol) } else { Text(actionTitle) }
                }
                .buttonStyle(.osPrimary)
                .padding(.top, Space.xs)
            }
        }
        .padding(Space.x3)
        .frame(maxWidth: .infinity)
    }
}

struct InlineErrorView: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
            Text(message).font(Typo.body).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.md)
        .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

// MARK: - Subject identity

struct SubjectDot: View {
    let colorKey: String
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(SubjectColor.from(colorKey).color).frame(width: size, height: size)
    }
}

struct SubjectChip: View {
    let subject: Subject?
    var body: some View {
        if let subject {
            HStack(spacing: 5) {
                SubjectDot(colorKey: subject.colorKey, size: 7)
                Text(subject.name).font(Typo.callout).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(SubjectColor.from(subject.colorKey).color.opacity(0.12), in: Capsule())
        }
    }
}

struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.badgeText)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Theme.badgeBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Checkboxes

struct TaskCheckbox: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(isOn ? Theme.ink : Theme.borderStrong, lineWidth: 1.5)
                if isOn {
                    Circle().fill(Theme.ink)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.onInk)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
        .accessibilityLabel(isOn ? "Mark incomplete" : "Mark complete")
    }
}

struct SquareCheckbox: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isOn ? Theme.ink : Theme.borderStrong, lineWidth: 1.5)
                if isOn {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.ink)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.onInk)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
        .accessibilityLabel(isOn ? "Uncheck" : "Check")
    }
}

// MARK: - Segmented pill

struct OSSegmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { option in
                let selected = option.0 == selection
                Button {
                    withAnimation(Motion.fade) { selection = option.0 }
                } label: {
                    Text(option.1)
                        .font(Typo.bodyMedium)
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.raised)
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border))
                                    .shadow(color: .black.opacity(0.05), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: "thumb", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

// MARK: - Fields

struct OSFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(Typo.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Theme.inputBorder))
    }
}

/// Placeholder text using the design system's placeholder colour.
func placeholder(_ text: String) -> Text {
    Text(text).foregroundStyle(Theme.placeholder)
}

extension TextFieldStyle where Self == OSFieldStyle {
    static var os: OSFieldStyle { OSFieldStyle() }
}

/// Labelled form row used in sheets.
struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Typo.callout.weight(.medium)).foregroundStyle(Theme.textSecondary)
            content()
        }
    }
}

/// Standard sheet chrome: title, content, footer buttons.
struct SheetScaffold<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String? = nil
    var width: CGFloat = 480
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typo.title).foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle).font(Typo.body).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Space.xxl)
            .padding(.top, Space.xxl)
            .padding(.bottom, Space.lg)

            content()
                .padding(.horizontal, Space.xxl)

            Divider().overlay(Theme.border).padding(.top, Space.xl)
            HStack(spacing: Space.sm) { footer() }
                .padding(.horizontal, Space.xxl)
                .padding(.vertical, Space.lg)
        }
        .frame(width: width)
        .background(Theme.surface)
    }
}

// MARK: - Progress bar

struct ThinProgress: View {
    let value: Double // 0...1
    var tint: Color = Theme.accent
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(tint).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: value)
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func duration(_ seconds: Double) -> String {
        let mins = Int((seconds / 60).rounded())
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func hoursValue(_ seconds: Double) -> (String, String) {
        let mins = seconds / 60
        if mins < 60 { return ("\(Int(mins.rounded()))", "min") }
        return (String(format: "%.1f", mins / 60), "hrs")
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
        if days > 0 && days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func interval(days: Double) -> String {
        if days < 1 { return "<1d" }
        if days < 30 { return "\(Int(days.rounded()))d" }
        if days < 365 { return "\(Int((days / 30).rounded()))mo" }
        return String(format: "%.1fy", days / 365)
    }
}

// MARK: - Flow layout

/// Lays children out left to right, wrapping onto new lines (chips, tags).
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = Space.s6
    var lineSpacing: CGFloat = Space.s6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap: CGFloat = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += size.width + gap
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

// MARK: - Pointer cursors

/// Hover cursors used by the editor chrome. `pointerStyle` needs macOS 15,
/// so older systems fall back to the matching AppKit cursor.
enum AppCursor {
    case grab, resizeHorizontal, resizeVertical

    @available(macOS 15.0, *)
    var pointerStyle: PointerStyle {
        switch self {
        case .grab: .grabIdle
        case .resizeHorizontal: .frameResize(position: .trailing)
        case .resizeVertical: .frameResize(position: .bottom)
        }
    }

    var nsCursor: NSCursor {
        switch self {
        case .grab: .openHand
        case .resizeHorizontal: .resizeLeftRight
        case .resizeVertical: .resizeUpDown
        }
    }
}

extension View {
    @ViewBuilder
    func appCursor(_ cursor: AppCursor) -> some View {
        if #available(macOS 15.0, *) {
            pointerStyle(cursor.pointerStyle)
        } else {
            onHover { inside in
                if inside { cursor.nsCursor.push() } else { NSCursor.pop() }
            }
        }
    }
}
