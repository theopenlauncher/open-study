//
//  BlockContainer.swift
//  open-study
//
//  Shared block chrome (DESIGN.md §8): hover gutter with + and drag handle,
//  the block menu, width/height resizing and drop targets for reordering.
//

import SwiftUI

struct BlockContainer<Content: View>: View {
    @Bindable var block: Block
    let columnWidth: CGFloat
    @Binding var inserterAnchor: UUID?
    let actions: BlockPageActions
    @ViewBuilder let content: () -> Content

    @State private var hovering = false
    @State private var dropTargeted = false
    @State private var showMenu = false
    @State private var dragStartWidth: CGFloat?
    @State private var dragStartHeight: Double?
    @State private var resizing = false

    private static var widths: [(Double, String)] { [(1, "Full width"), (2.0 / 3, "Two-thirds"), (0.5, "Half"), (1.0 / 3, "One-third")] }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) { gutter }
            .overlay(alignment: .trailing) { widthHandle }
            .overlay(alignment: .bottom) { heightHandle }
            .overlay(alignment: .top) {
                if dropTargeted { DropLine().offset(y: -4) }
            }
            .padding(.leading, Layout.blockGutter)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .padding(.leading, -Layout.blockGutter)
            .animation(Motion.hover, value: hovering)
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first.flatMap(UUID.init) else { return false }
                actions.move(id, block.id)
                return true
            } isTargeted: { dropTargeted = $0 }
            .contextMenu { menuItems }
    }

    // MARK: Gutter

    private var showChrome: Bool { hovering || showMenu || inserterAnchor == block.id || resizing }

    private var gutter: some View {
        HStack(spacing: 0) {
            gutterButton("plus", help: "Insert block below") { inserterAnchor = block.id }
                .popover(isPresented: Binding(get: { inserterAnchor == block.id }, set: { if !$0 { inserterAnchor = nil } }),
                         arrowEdge: .bottom) {
                    BlockInserter { kind in actions.insert(kind, block) }
                }
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 20, height: 22)
                .hoverHighlight(cornerRadius: 5)
                .contentShape(Rectangle())
                .appCursor(.grab)
                .help("Drag to move · Click for options")
                .onTapGesture { showMenu = true }
                .draggable(block.id.uuidString) {
                    HStack(spacing: 6) {
                        Image(systemName: block.kind.symbol)
                        Text(dragLabel).lineLimit(1)
                    }
                    .font(Typo.bodyMedium)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.control))
                }
                .popover(isPresented: $showMenu, arrowEdge: .leading) { menuPopover }
                .accessibilityLabel("Block options")
                .accessibilityAddTraits(.isButton)
        }
        .padding(.top, block.kind.isInline ? 2 : 6)
        .frame(width: Layout.blockGutter, alignment: .leading)
        .offset(x: -Layout.blockGutter)
        .opacity(showChrome ? 1 : 0)
    }

    private func gutterButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 20, height: 22)
                .hoverHighlight(cornerRadius: 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var dragLabel: String {
        let t = block.kind == .tasks || block.kind == .checklist ? block.title : block.text
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? block.kind.title : String(trimmed.prefix(40))
    }

    // MARK: Menu

    @ViewBuilder private var menuItems: some View {
        if block.kind.supportsWidth {
            Menu("Width") {
                ForEach(Self.widths, id: \.0) { w in
                    Button {
                        withAnimation(Motion.fade) { block.widthFraction = w.0 }
                    } label: {
                        if abs(block.widthFraction - w.0) < 0.01 { Label(w.1, systemImage: "checkmark") } else { Text(w.1) }
                    }
                }
            }
        }
        if block.kind == .heading {
            Menu("Heading Level") {
                ForEach(1...3, id: \.self) { level in
                    Button("Heading \(level)") { block.level = level }
                }
            }
        }
        if block.kind == .callout {
            Menu("Colour") {
                ForEach(CalloutTone.allCases) { tone in
                    Button(tone.rawValue.capitalized) { block.tone = tone }
                }
            }
        }
        if block.kind.isInline {
            Button("Duplicate") { actions.duplicate(block) }
        }
        Divider()
        Button("Move Up") { actions.shift(block, -1) }
        Button("Move Down") { actions.shift(block, 1) }
        Divider()
        Button("Delete", role: .destructive) { actions.requestDelete(block) }
    }

    private var menuPopover: some View {
        VStack(alignment: .leading, spacing: 1) {
            if block.kind.supportsWidth {
                SectionLabel("Width").padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 2)
                HStack(spacing: 4) {
                    ForEach(Self.widths, id: \.0) { w in
                        let selected = abs(block.widthFraction - w.0) < 0.01
                        Button {
                            withAnimation(Motion.fade) { block.widthFraction = w.0 }
                        } label: {
                            Text(w.0 == 1 ? "Full" : w.0 > 0.6 ? "⅔" : w.0 == 0.5 ? "½" : "⅓")
                                .font(Typo.bodyMedium)
                                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                                .frame(width: 44, height: 26)
                                .background(selected ? Theme.muted : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Theme.borderStrong : Theme.border))
                        }
                        .buttonStyle(.plain)
                        .help(w.1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                Divider().overlay(Theme.border).padding(.vertical, 2)
            }
            if block.kind == .heading {
                menuRow("Heading 1", "textformat.size.larger") { block.level = 1 }
                menuRow("Heading 2", "textformat.size") { block.level = 2 }
                menuRow("Heading 3", "textformat.size.smaller") { block.level = 3 }
                Divider().overlay(Theme.border).padding(.vertical, 2)
            }
            if block.kind == .callout {
                HStack(spacing: 6) {
                    ForEach(CalloutTone.allCases) { tone in
                        Button { block.tone = tone } label: {
                            Circle().fill(CalloutBlockView.fill(tone))
                                .overlay(Circle().strokeBorder(block.tone == tone ? Theme.ink : Theme.border, lineWidth: block.tone == tone ? 1.5 : 1))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help(tone.rawValue.capitalized)
                    }
                }
                .padding(8)
                Divider().overlay(Theme.border).padding(.vertical, 2)
            }
            if block.kind.isInline { menuRow("Duplicate", "plus.square.on.square") { actions.duplicate(block) } }
            menuRow("Move up", "arrow.up") { actions.shift(block, -1) }
            menuRow("Move down", "arrow.down") { actions.shift(block, 1) }
            Divider().overlay(Theme.border).padding(.vertical, 2)
            menuRow("Delete", "trash", destructive: true) { actions.requestDelete(block) }
        }
        .padding(6)
        .frame(width: 220)
    }

    private func menuRow(_ title: String, _ symbol: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            showMenu = false
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
                Spacer()
            }
            .font(Typo.body)
            .foregroundStyle(destructive ? Theme.danger : Theme.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
            .hoverHighlight(cornerRadius: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: Resizing

    @ViewBuilder private var widthHandle: some View {
        if block.kind.supportsWidth {
            Capsule()
                .fill(resizing ? Theme.accent : Theme.borderStrong)
                .frame(width: 4, height: 32)
                .frame(width: 12, height: 48)
                .contentShape(Rectangle())
                .appCursor(.resizeHorizontal)
                .offset(x: 9)
                .opacity(showChrome ? 1 : 0)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            resizing = true
                            let start = dragStartWidth ?? CGFloat(block.widthFraction) * columnWidth
                            dragStartWidth = start
                            let fraction = Double((start + value.translation.width) / max(1, columnWidth))
                            let snapped = Self.widths.map(\.0).min { abs($0 - fraction) < abs($1 - fraction) } ?? 1
                            if abs(snapped - block.widthFraction) > 0.01 {
                                withAnimation(Motion.fade) { block.widthFraction = snapped }
                            }
                        }
                        .onEnded { _ in
                            dragStartWidth = nil
                            resizing = false
                        }
                )
                .help("Drag to resize")
        }
    }

    @ViewBuilder private var heightHandle: some View {
        if block.kind.supportsHeight {
            Capsule()
                .fill(resizing ? Theme.accent : Theme.borderStrong)
                .frame(width: 32, height: 4)
                .frame(width: 60, height: 12)
                .contentShape(Rectangle())
                .appCursor(.resizeVertical)
                .offset(y: 7)
                .opacity(showChrome ? 1 : 0)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            resizing = true
                            let start = dragStartHeight ?? block.height
                            dragStartHeight = start
                            block.height = min(1400, max(240, start + value.translation.height))
                        }
                        .onEnded { _ in
                            dragStartHeight = nil
                            resizing = false
                        }
                )
                .help("Drag to change height")
        }
    }
}

/// Routes a block to its view.
struct BlockContent: View {
    let block: Block
    let formatter: NoteFormatter
    @Binding var focusBlockID: UUID?
    let onSlash: () -> Void

    var body: some View {
        switch block.kind {
        case .text:
            RichTextEditor(block: block, formatter: formatter, autoFocus: focusBlockID == block.id,
                           onSlash: onSlash, onAutoFocused: { focusBlockID = nil })
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 1)
        case .heading: HeadingBlockView(block: block)
        case .divider: DividerBlockView()
        case .callout: CalloutBlockView(block: block)
        case .checklist: ChecklistBlockView(block: block)
        case .tasks: TaskListBlockView(block: block)
        case .flashcards: FlashcardsBlockView(block: block)
        case .pdf: PDFBlockView(block: block)
        case .pomodoro: PomodoroBlockView(block: block)
        case .statistics: StatisticsBlockView(block: block)
        case .quiz: QuizBlockView(block: block)
        }
    }
}
