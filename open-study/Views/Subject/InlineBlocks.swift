//
//  InlineBlocks.swift
//  open-study
//
//  Borderless document blocks: heading, divider, callout, checklist.
//

import SwiftUI

struct HeadingBlockView: View {
    @Bindable var block: Block

    private var font: Font {
        switch block.level {
        case 1: Typo.h1
        case 2: Typo.h2
        default: Typo.h3
        }
    }

    var body: some View {
        TextField("Heading \(block.level)", text: $block.text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(Theme.textPrimary)
            .padding(.top, block.level == 1 ? Space.md : Space.sm)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

struct DividerBlockView: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.vertical, Space.md)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Divider")
    }
}

struct CalloutBlockView: View {
    @Bindable var block: Block

    static let symbols = ["lightbulb", "info.circle", "exclamationmark.triangle", "star", "bookmark",
                          "pin", "graduationcap", "brain", "flag", "quote.opening"]

    static func fill(_ tone: CalloutTone) -> Color {
        switch tone {
        case .neutral: Theme.muted
        case .blue: Theme.accent.opacity(0.10)
        case .green: Theme.success.opacity(0.10)
        case .yellow: Theme.warning.opacity(0.12)
        case .red: Theme.danger.opacity(0.10)
        }
    }

    static func tint(_ tone: CalloutTone) -> Color {
        switch tone {
        case .neutral: Theme.textSecondary
        case .blue: Theme.accent
        case .green: Theme.success
        case .yellow: Theme.warning
        case .red: Theme.danger
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.md) {
            Menu {
                ForEach(Self.symbols, id: \.self) { s in
                    Button { block.symbol = s } label: { Label(s, systemImage: s) }
                }
            } label: {
                Image(systemName: block.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(Self.tint(block.tone))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change icon")

            TextField("Write a callout…", text: $block.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Typo.reading)
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(3)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.fill(block.tone), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(.vertical, Space.xs)
    }
}

struct ChecklistBlockView: View {
    @Bindable var block: Block
    @FocusState private var focused: UUID?
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    private var items: [ChecklistEntry] { block.checklist }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                TextField("Checklist", text: $block.title)
                    .textFieldStyle(.plain)
                    .font(Typo.headline)
                    .foregroundStyle(Theme.textPrimary)
                if !items.isEmpty {
                    Text("\(items.filter(\.done).count) of \(items.count)")
                        .font(Typo.callout.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.bottom, Space.xs)

            ForEach(items) { item in
                row(item)
            }

            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary).frame(width: 16)
                TextField("Add an item", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Typo.reading)
                    .focused($draftFocused)
                    .onSubmit(addDraft)
            }
            .frame(minHeight: 28)
        }
        .padding(.vertical, Space.xs)
    }

    private func row(_ item: ChecklistEntry) -> some View {
        HStack(spacing: 10) {
            SquareCheckbox(isOn: item.done) { update(item.id) { $0.done.toggle() } }
            TextField("Item", text: Binding(
                get: { block.checklist.first { $0.id == item.id }?.text ?? "" },
                set: { new in update(item.id) { $0.text = new } }
            ))
            .textFieldStyle(.plain)
            .font(Typo.reading)
            .foregroundStyle(item.done ? Theme.textTertiary : Theme.textPrimary)
            .strikethrough(item.done, color: Theme.textTertiary)
            .focused($focused, equals: item.id)
            .onSubmit { insertAfter(item.id) }
            ItemDeleteButton { remove(item.id) }
        }
        .frame(minHeight: 28)
    }

    private func update(_ id: UUID, _ change: (inout ChecklistEntry) -> Void) {
        var list = block.checklist
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        block.checklist = list
    }

    private func insertAfter(_ id: UUID) {
        var list = block.checklist
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        if list[i].text.trimmingCharacters(in: .whitespaces).isEmpty { draftFocused = true; return }
        let entry = ChecklistEntry(text: "")
        list.insert(entry, at: i + 1)
        block.checklist = list
        DispatchQueue.main.async { focused = entry.id }
    }

    private func remove(_ id: UUID) {
        block.checklist = block.checklist.filter { $0.id != id }
    }

    private func addDraft() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        block.checklist = block.checklist + [ChecklistEntry(text: text)]
        draft = ""
        draftFocused = true
    }
}

/// Small × that appears on row hover.
struct ItemDeleteButton: View {
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? Theme.danger : Theme.textTertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Remove")
        .accessibilityLabel("Remove")
    }
}
