//
//  HabitViews.swift
//  open-study
//
//  Simple daily study habits with streaks and history.
//

import SwiftUI
import SwiftData

enum HabitLogic {
    static func toggle(_ habit: Habit, on day: Date, context: ModelContext) {
        let d = Calendar.current.startOfDay(for: day)
        if let existing = habit.checks.first(where: { Calendar.current.isDate($0.day, inSameDayAs: d) }) {
            context.delete(existing)
        } else {
            let check = HabitCheck(day: d)
            context.insert(check)
            check.habit = habit
        }
        try? context.save()
    }
}

/// Today's habits, shown on Home.
struct HabitsSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.sortIndex) private var habits: [Habit]
    @State private var showManager = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            SectionLabel("Habits") {
                Button(habits.isEmpty ? "Add habit" : "Manage") { showManager = true }
                    .buttonStyle(OSButtonStyle(variant: .ghost, compact: true))
            }
            if habits.isEmpty {
                Text("Build routines like “Review flashcards” or “Read for 20 minutes” and tick them off each day.")
                    .font(Typo.callout).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(habits.enumerated()), id: \.element.id) { i, habit in
                        if i > 0 { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 44) }
                        HabitRow(habit: habit)
                    }
                }
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.border))
            }
        }
        .sheet(isPresented: $showManager) { HabitsManager() }
    }
}

struct HabitRow: View {
    let habit: Habit
    @Environment(\.modelContext) private var context

    var body: some View {
        let days = Calendar.current.days(back: 7)
        let checked = habit.checkedDays
        HStack(spacing: Space.md) {
            TaskCheckbox(isOn: checked.contains(Calendar.current.startOfDay(for: .now))) {
                withAnimation(Motion.fade) { HabitLogic.toggle(habit, on: .now, context: context) }
            }
            Image(systemName: habit.symbol).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).frame(width: 18)
            Text(habit.name).font(Typo.body).lineLimit(1)
            Spacer()
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    Circle()
                        .fill(checked.contains(day) ? Theme.ink : Theme.muted)
                        .frame(width: 8, height: 8)
                        .help(day.formatted(.dateTime.weekday(.wide)))
                }
            }
            let streak = Streaks.current(days: checked)
            Text(streak == 0 ? "—" : "\(streak) day\(streak == 1 ? "" : "s")")
                .font(Typo.callout.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, Space.md)
        .frame(height: 42)
    }
}

struct HabitsManager: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.sortIndex) private var habits: [Habit]
    @State private var name = ""
    @State private var symbol = "checkmark.circle"
    @State private var toDelete: Habit?

    static let symbols = ["checkmark.circle", "book", "rectangle.on.rectangle.angled", "timer", "pencil", "brain.head.profile",
                          "figure.walk", "moon.zzz", "drop", "music.note", "globe", "sun.max"]

    var body: some View {
        SheetScaffold(title: "Habits", subtitle: "Tick a habit off each day you do it. Streaks count consecutive days.", width: 600) {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(spacing: Space.sm) {
                    Menu {
                        ForEach(Self.symbols, id: \.self) { s in Button { symbol = s } label: { Label(s, systemImage: s) } }
                    } label: { Image(systemName: symbol) }
                    .menuStyle(.button).buttonStyle(.osSecondary).fixedSize()
                    TextField("New habit, e.g. Review flashcards", text: $name)
                        .textFieldStyle(.os)
                        .onSubmit(add)
                    Button("Add", action: add).buttonStyle(.osPrimary)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ScrollView {
                    VStack(spacing: Space.md) {
                        ForEach(habits) { habit in
                            HabitHistoryCard(habit: habit) { toDelete = habit }
                        }
                    }
                }
                .frame(height: 380)
            }
        } footer: {
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(.osPrimary).keyboardShortcut(.defaultAction)
        }
        .confirmationDialog("Delete “\(toDelete?.name ?? "")”?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Habit", role: .destructive) {
                if let toDelete { context.delete(toDelete) }
                try? context.save()
                toDelete = nil
            }
        } message: { Text("Its history will be deleted too.") }
    }

    private func add() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        context.insert(Habit(name: n, symbol: symbol, sortIndex: (habits.map(\.sortIndex).max() ?? -1) + 1))
        try? context.save()
        name = ""
    }
}

private struct HabitHistoryCard: View {
    @Bindable var habit: Habit
    let onDelete: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        let checked = habit.checkedDays
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Image(systemName: habit.symbol).foregroundStyle(Theme.textSecondary)
                TextField("Habit", text: $habit.name).textFieldStyle(.plain).font(Typo.headline)
                Spacer()
                Text("Current \(Streaks.current(days: checked)) · Longest \(Streaks.longest(days: checked))")
                    .font(Typo.callout.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                IconButton(symbol: "trash", help: "Delete habit", size: 24, action: onDelete)
            }
            Heatmap(values: Dictionary(uniqueKeysWithValues: checked.map { ($0, 100.0) }), weeks: 16)
                .frame(height: 7 * 14 + 6 * 3)
            Text("Click a past day in the grid below to fix a missed check-in.")
                .font(Typo.callout).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 4) {
                ForEach(Calendar.current.days(back: 14), id: \.self) { day in
                    Button {
                        HabitLogic.toggle(habit, on: day, context: context)
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                            RoundedRectangle(cornerRadius: 3).fill(checked.contains(day) ? Theme.ink : Theme.muted).frame(width: 16, height: 16)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(day.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .cardStyle()
    }
}
