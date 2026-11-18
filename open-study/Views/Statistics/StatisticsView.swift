//
//  StatisticsView.swift
//  open-study
//
//  Progress computed entirely from recorded activity — never sample data.
//

import SwiftUI
import SwiftData
import Charts

struct StatisticsView: View {
    @Query private var sessions: [FocusSession]
    @Query private var reviews: [ReviewLog]
    @Query private var tasks: [TaskItem]
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]
    @AppStorage("stats.range") private var range = 30

    private var cal: Calendar { .current }
    private var rangeStart: Date { cal.date(byAdding: .day, value: -(range - 1), to: cal.startOfDay(for: .now))! }

    private var all: ActivitySummary { ActivitySummary(sessions: sessions, reviews: reviews, tasks: tasks) }
    private var inRange: ActivitySummary {
        ActivitySummary(sessions: sessions.filter { $0.startedAt >= rangeStart },
                        reviews: reviews.filter { $0.date >= rangeStart },
                        tasks: tasks.filter { ($0.completedAt ?? .distantPast) >= rangeStart })
    }

    var body: some View {
        PageScroll {
            PageHeader(title: "Statistics", subtitle: "Your study activity, measured from what you actually do.") {
                if all.hasAnyData {
                    OSSegmented(options: [(7, "7 days"), (30, "30 days"), (90, "90 days")], selection: $range)
                }
            }
            .padding(.bottom, Space.xxl)

            if !all.hasAnyData {
                OSCard {
                    EmptyStateView(symbol: "chart.bar.xaxis", title: "Your stats appear as you study",
                                   message: "Complete a focus session, review some flashcards or finish a task, and your progress will show up here. Nothing is estimated or made up.")
                }
            } else {
                content
            }
        }
    }

    @ViewBuilder private var content: some View {
        let r = inRange
        let days = cal.days(back: range)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.md), count: 4), spacing: Space.md) {
            let (tv, tu) = Fmt.hoursValue(all.totalFocusSeconds)
            StatTile(value: tv, unit: tu, caption: "total study time")
            let (rv, ru) = Fmt.hoursValue(r.totalFocusSeconds)
            StatTile(value: rv, unit: ru, caption: "studied in \(range) days")
            let (dv, du) = Fmt.hoursValue(all.focusSeconds(on: .now))
            StatTile(value: dv, unit: du, caption: "today")
            StatTile(value: "\(r.completedPomodoros)", unit: "pomodoros", caption: "completed")
            StatTile(value: "\(r.reviewCount)", unit: "cards", caption: "reviewed")
            StatTile(value: r.accuracy.map { "\(Int(($0 * 100).rounded()))" } ?? "—", unit: r.accuracy == nil ? "" : "%", caption: "flashcard accuracy")
            StatTile(value: "\(r.tasksCompleted)", unit: "tasks", caption: "completed")
            StatTile(value: "\(Streaks.current(days: all.studyDays))", unit: "days",
                     caption: "streak · best \(Streaks.longest(days: all.studyDays))")
        }
        .padding(.bottom, Space.xxl)

        HStack(alignment: .top, spacing: Space.lg) {
            chartCard("Study time per day", caption: "Minutes of focus") {
                Chart(days, id: \.self) { day in
                    BarMark(x: .value("Day", day, unit: .day), y: .value("Minutes", r.focusSeconds(on: day) / 60))
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .cornerRadius(2)
                }
                .modifier(QuietAxes(range: range))
            }
            chartCard("Flashcard reviews", caption: "Cards reviewed per day") {
                Chart(days, id: \.self) { day in
                    BarMark(x: .value("Day", day, unit: .day), y: .value("Reviews", r.reviews(on: day)))
                        .foregroundStyle(Theme.accent)
                        .cornerRadius(2)
                }
                .modifier(QuietAxes(range: range))
                .overlay {
                    if r.reviewCount == 0 {
                        Text("No reviews in this period yet").font(Typo.callout).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(.bottom, Space.lg)

        HStack(alignment: .top, spacing: Space.lg) {
            chartCard("Focus by subject", caption: "Last \(range) days") {
                let rows = subjectRows(r)
                if rows.isEmpty {
                    Text("Pick a subject in Focus mode or a subject's Pomodoro block to see a breakdown.")
                        .font(Typo.callout).foregroundStyle(Theme.textTertiary).frame(maxHeight: .infinity)
                } else {
                    Chart(rows, id: \.name) { row in
                        BarMark(x: .value("Minutes", row.minutes), y: .value("Subject", row.name), height: .fixed(16))
                            .foregroundStyle(row.color)
                            .cornerRadius(2)
                            .annotation(position: .trailing) {
                                Text(Fmt.duration(row.minutes * 60)).font(Typo.callout).foregroundStyle(Theme.textSecondary)
                            }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks { _ in AxisValueLabel().font(Typo.callout) }
                    }
                }
            }
            chartCard("Activity", caption: "Last 20 weeks · darker means more study") {
                Heatmap(values: all.activityByDay)
            }
        }
    }

    private struct SubjectRow { let name: String; let minutes: Double; let color: Color }

    private func subjectRows(_ r: ActivitySummary) -> [SubjectRow] {
        var rows: [SubjectRow] = subjects.compactMap { s in
            let m = r.sessions.filter { $0.subject?.id == s.id }.reduce(0) { $0 + $1.seconds } / 60
            return m > 0 ? SubjectRow(name: s.name, minutes: m, color: SubjectColor.from(s.colorKey).color) : nil
        }
        let unassigned = r.sessions.filter { $0.subject == nil }.reduce(0) { $0 + $1.seconds } / 60
        if unassigned > 0 && !rows.isEmpty { rows.append(SubjectRow(name: "No subject", minutes: unassigned, color: Theme.textTertiary)) }
        return rows.sorted { $0.minutes > $1.minutes }
    }

    private func chartCard<C: View>(_ title: String, caption: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.headline)
                Text(caption).font(Typo.callout).foregroundStyle(Theme.textTertiary)
            }
            content().frame(height: 180)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct QuietAxes: ViewModifier {
    let range: Int
    func body(content: Content) -> some View {
        content
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range <= 7 ? 1 : range <= 30 ? 7 : 21)) { _ in
                    AxisValueLabel(format: range <= 7 ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])).foregroundStyle(Theme.border)
                    AxisValueLabel()
                }
            }
    }
}

struct Heatmap: View {
    let values: [Date: Double]
    var weeks = 20

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let weekday = (cal.component(.weekday, from: today) - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7 - weekday, to: today)!
        GeometryReader { geo in
            let cell = min(14, (geo.size.width - CGFloat(weeks - 1) * 3) / CGFloat(weeks))
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            let v = values[day] ?? 0
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(day > today ? Color.clear : (v <= 0 ? Theme.muted : Theme.ink.opacity(level(v))))
                                .frame(width: cell, height: cell)
                                .help(day > today ? "" : "\(day.formatted(date: .abbreviated, time: .omitted)): \(v > 0 ? "\(Int(v.rounded())) activity points" : "no activity")")
                        }
                    }
                }
            }
        }
        .accessibilityLabel("Activity heatmap for the last \(weeks) weeks")
    }

    private func level(_ v: Double) -> Double {
        switch v {
        case ..<15: 0.15
        case ..<45: 0.35
        case ..<90: 0.6
        default: 0.85
        }
    }
}
