//
//  BlockInserter.swift
//  open-study
//
//  The shared "/" command menu and "+" popover (DESIGN.md §13 Subject page).
//

import SwiftUI

struct BlockInserter: View {
    let onPick: (BlockKind) -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private static let basic: [BlockKind] = [.text, .heading, .callout, .checklist, .divider]
    private static let tools: [BlockKind] = [.tasks, .flashcards, .pdf, .quiz, .pomodoro, .statistics]

    private var filtered: [BlockKind] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let all = Self.basic + Self.tools
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) || $0.keywords.contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                TextField("Search blocks", text: $query)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .focused($searchFocused)
                    .onSubmit(pickHighlighted)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
            }
            .padding(.horizontal, Space.md)
            .frame(height: 36)

            Divider().overlay(Theme.border)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        if filtered.isEmpty {
                            Text("No blocks match “\(query)”")
                                .font(Typo.body)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(Space.md)
                        }
                        ForEach(Array(filtered.enumerated()), id: \.element) { index, kind in
                            if query.isEmpty && index == 0 { groupLabel("Basic") }
                            if query.isEmpty && index == Self.basic.count { groupLabel("Study tools") }
                            row(kind, highlighted: index == highlighted)
                                .id(kind)
                                .onTapGesture { onPick(kind) }
                                .onHover { if $0 { highlighted = index } }
                        }
                    }
                    .padding(Space.xs)
                }
                .onChange(of: highlighted) { _, new in
                    if filtered.indices.contains(new) { proxy.scrollTo(filtered[new]) }
                }
            }
            .frame(maxHeight: 340)
        }
        .frame(width: 300)
        .background(Theme.raised)
        .onAppear { searchFocused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    private func groupLabel(_ text: String) -> some View {
        SectionLabel(text).padding(.horizontal, Space.sm).padding(.top, Space.sm).padding(.bottom, 2)
    }

    private func row(_ kind: BlockKind, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(Typo.bodyMedium).foregroundStyle(Theme.textPrimary)
                Text(kind.subtitle).font(Typo.callout).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(highlighted ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func move(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        highlighted = (highlighted + delta + filtered.count) % filtered.count
    }

    private func pickHighlighted() {
        guard filtered.indices.contains(highlighted) else { return }
        onPick(filtered[highlighted])
    }
}
