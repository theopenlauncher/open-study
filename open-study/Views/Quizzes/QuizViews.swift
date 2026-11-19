//
//  QuizViews.swift
//  open-study
//
//  Simple practice tests: multiple choice, true/false and short answer.
//

import SwiftUI
import SwiftData
import PostHog

struct QuizzesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Quiz.createdAt, order: .reverse) private var quizzes: [Quiz]
    @State private var editing: Quiz?
    @State private var taking: Quiz?
    @State private var toDelete: Quiz?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { newQuiz() } label: { Label("New quiz", systemImage: "plus") }
                    .buttonStyle(.osPrimary)
                Spacer()
            }
            .padding(.bottom, Space.xxl)

            if quizzes.isEmpty {
                OSCard {
                    EmptyStateView(symbol: "questionmark.square.dashed", title: "No quizzes yet",
                                   message: "Write a few questions to test yourself before an exam. You'll get a score and can review what you missed.",
                                   actionTitle: "New quiz", actionSymbol: "plus", action: newQuiz)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Space.lg)], spacing: Space.lg) {
                    ForEach(quizzes) { quiz in
                        QuizCard(quiz: quiz, onEdit: { editing = quiz }, onTake: { taking = quiz }, onDelete: { toDelete = quiz })
                    }
                }
            }
        }
        .sheet(item: $editing) { QuizEditorView(quiz: $0) }
        .sheet(item: $taking) { QuizRunnerView(quiz: $0) }
        .confirmationDialog("Delete “\(toDelete?.title ?? "")”?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete Quiz", role: .destructive) {
                if let toDelete { context.delete(toDelete) }
                try? context.save()
                toDelete = nil
            }
        } message: { Text("Its questions and past scores will be deleted.") }
    }

    private func newQuiz() {
        let quiz = Quiz(title: "")
        context.insert(quiz)
        editing = quiz
    }
}

struct QuizCard: View {
    let quiz: Quiz
    let onEdit: () -> Void
    let onTake: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let ready = quiz.questions.filter(\.isComplete).count
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .top) {
                Text(quiz.title.isEmpty ? "Untitled quiz" : quiz.title).font(Typo.headline).lineLimit(2)
                Spacer()
                SubjectChip(subject: quiz.subject)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(quiz.questions.count)").font(Typo.numeralSmall)
                Text(quiz.questions.count == 1 ? "question" : "questions").font(Typo.body).foregroundStyle(Theme.textSecondary)
                Spacer()
                if let best = quiz.bestScore {
                    Text("Best \(Int((best * 100).rounded()))%").font(Typo.callout).foregroundStyle(Theme.textTertiary)
                }
            }
            HStack {
                Button("Edit", action: onEdit).buttonStyle(OSButtonStyle(variant: .ghost, compact: true))
                Spacer()
                Button("Take quiz", action: onTake).buttonStyle(OSButtonStyle(variant: .secondary, compact: true))
                    .disabled(ready == 0)
            }
        }
        .cardStyle()
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Take Quiz", action: onTake).disabled(ready == 0)
            Divider()
            Button("Delete Quiz…", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Editor

struct QuizEditorView: View {
    @Bindable var quiz: Quiz
    var lockedSubject: Subject? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Subject.sortIndex) private var subjects: [Subject]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                TextField("Quiz title", text: $quiz.title)
                    .textFieldStyle(.plain)
                    .font(Typo.title)
                Spacer()
                if lockedSubject == nil {
                    Picker("Subject", selection: Binding(get: { quiz.subject?.id }, set: { id in quiz.subject = subjects.first { $0.id == id } })) {
                        Text("No subject").tag(UUID?.none)
                        ForEach(subjects) { s in Text(s.name).tag(UUID?.some(s.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.horizontal, Space.xxl)
            .padding(.vertical, Space.lg)

            Divider().overlay(Theme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if quiz.questions.isEmpty {
                        Text("Add your first question below.").font(Typo.body).foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(Array(quiz.sortedQuestions.enumerated()), id: \.element.id) { i, q in
                        QuestionEditor(question: q, number: i + 1) {
                            context.delete(q)
                            renumber()
                        }
                    }
                    HStack(spacing: Space.sm) {
                        ForEach(QuestionKind.allCases) { kind in
                            Button { add(kind) } label: { Label(kind.title, systemImage: "plus") }
                                .buttonStyle(.osSecondary)
                        }
                    }
                }
                .padding(Space.xxl)
            }

            Divider().overlay(Theme.border)
            HStack {
                let incomplete = quiz.questions.filter { !$0.isComplete }.count
                if incomplete > 0 {
                    Label("\(incomplete) question\(incomplete == 1 ? " needs" : "s need") an answer and will be skipped", systemImage: "exclamationmark.circle")
                        .font(Typo.callout).foregroundStyle(Theme.warning)
                }
                Spacer()
                Button("Done") {
                    if quiz.title.trimmingCharacters(in: .whitespaces).isEmpty { quiz.title = "Untitled quiz" }
                    try? context.save()
                    dismiss()
                }
                .buttonStyle(.osPrimary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.xxl)
            .padding(.vertical, Space.lg)
        }
        .frame(width: 680, height: 640)
        .background(Theme.surface)
        .onAppear {
            if let lockedSubject, quiz.subject == nil { quiz.subject = lockedSubject }
        }
    }

    private func add(_ kind: QuestionKind) {
        let q = QuizQuestion(kind: kind, sortIndex: (quiz.questions.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(q)
        q.quiz = quiz
    }

    private func renumber() {
        for (i, q) in quiz.sortedQuestions.enumerated() { q.sortIndex = i }
    }
}

struct QuestionEditor: View {
    @Bindable var question: QuizQuestion
    let number: Int
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Question \(number)").font(Typo.label).tracking(0.6).foregroundStyle(Theme.textTertiary)
                Spacer()
                Picker("Type", selection: Binding(get: { question.kind }, set: { question.kind = $0 })) {
                    ForEach(QuestionKind.allCases) { k in Text(k.title).tag(k) }
                }
                .labelsHidden()
                .fixedSize()
                IconButton(symbol: "trash", help: "Delete question", size: 26, action: onDelete)
            }
            TextField("Question", text: $question.prompt, axis: .vertical)
                .textFieldStyle(.os)
                .lineLimit(1...5)

            switch question.kind {
            case .multipleChoice:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(question.options.indices, id: \.self) { i in
                        HStack(spacing: Space.sm) {
                            Button { question.correctIndex = i } label: {
                                Image(systemName: question.correctIndex == i ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(question.correctIndex == i ? Theme.success : Theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Mark as the correct answer")
                            TextField("Option \(i + 1)", text: Binding(
                                get: { question.options[safe: i] ?? "" },
                                set: { v in if question.options.indices.contains(i) { question.options[i] = v } }
                            ))
                            .textFieldStyle(.os)
                            if question.options.count > 2 {
                                ItemDeleteButton {
                                    question.options.remove(at: i)
                                    if question.correctIndex >= question.options.count { question.correctIndex = 0 }
                                }
                            }
                        }
                    }
                    if question.options.count < 6 {
                        Button { question.options.append("") } label: { Label("Add option", systemImage: "plus") }
                            .buttonStyle(OSButtonStyle(variant: .ghost, compact: true))
                    }
                    Text("Select the circle next to the correct answer.").font(Typo.callout).foregroundStyle(Theme.textTertiary)
                }
            case .trueFalse:
                Picker("Correct answer", selection: $question.correctBool) {
                    Text("True").tag(true)
                    Text("False").tag(false)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            case .shortAnswer:
                TextField("Accepted answer — separate alternatives with |", text: $question.correctText)
                    .textFieldStyle(.os)
                Text("Answers are checked ignoring capitals and extra spaces.").font(Typo.callout).foregroundStyle(Theme.textTertiary)
            }
        }
        .cardStyle()
    }
}

// MARK: - Runner

struct QuizRunnerView: View {
    let quiz: Quiz
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    struct Answer { var choice: Int?; var bool: Bool?; var text: String = "" }

    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var answers: [UUID: Answer] = [:]
    @State private var checked = false
    @State private var finished = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quiz.title).font(Typo.title)
                    if !finished && !questions.isEmpty {
                        Text("Question \(index + 1) of \(questions.count)").font(Typo.callout).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Button(finished ? "Done" : "Quit") { dismiss() }.buttonStyle(.osGhost).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Space.xxl).padding(.top, Space.xl).padding(.bottom, Space.md)
            ThinProgress(value: questions.isEmpty ? 0 : Double(finished ? questions.count : index) / Double(questions.count), height: 3)
                .padding(.horizontal, Space.xxl)

            if finished { results } else if let q = questions[safe: index] { questionView(q) }
        }
        .frame(width: 640, height: 560)
        .background(Theme.surface)
        .onAppear { questions = quiz.sortedQuestions.filter(\.isComplete) }
    }

    private func binding(_ q: QuizQuestion) -> Binding<Answer> {
        Binding(get: { answers[q.id] ?? Answer() }, set: { answers[q.id] = $0 })
    }

    private func questionView(_ q: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Text(q.prompt).font(.system(size: 19)).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    switch q.kind {
                    case .multipleChoice:
                        VStack(spacing: Space.sm) {
                            ForEach(Array(q.options.enumerated()).filter { !$0.element.trimmingCharacters(in: .whitespaces).isEmpty }, id: \.offset) { i, option in
                                optionRow(option, selected: binding(q).wrappedValue.choice == i,
                                          state: checked ? (i == q.correctIndex ? .correct : (binding(q).wrappedValue.choice == i ? .wrong : .none)) : .none) {
                                    if !checked { binding(q).wrappedValue.choice = i }
                                }
                            }
                        }
                    case .trueFalse:
                        HStack(spacing: Space.sm) {
                            ForEach([true, false], id: \.self) { value in
                                optionRow(value ? "True" : "False", selected: binding(q).wrappedValue.bool == value,
                                          state: checked ? (value == q.correctBool ? .correct : (binding(q).wrappedValue.bool == value ? .wrong : .none)) : .none) {
                                    if !checked { binding(q).wrappedValue.bool = value }
                                }
                            }
                        }
                    case .shortAnswer:
                        VStack(alignment: .leading, spacing: Space.sm) {
                            TextField("Your answer", text: binding(q).text)
                                .textFieldStyle(.os)
                                .disabled(checked)
                                .onSubmit { if !checked { checked = true } }
                            if checked {
                                Text("Accepted: \(q.correctText.replacingOccurrences(of: "|", with: " or "))")
                                    .font(Typo.callout).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if checked {
                    let ok = isCorrect(q)
                    Label(ok ? "Correct" : "Not quite", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(Typo.headline).foregroundStyle(ok ? Theme.success : Theme.danger)
                }
                Spacer()
                if checked {
                    Button(index + 1 == questions.count ? "See results" : "Next question") { next() }
                        .buttonStyle(.osPrimary).keyboardShortcut(.defaultAction)
                } else {
                    Button("Check answer") { checked = true }
                        .buttonStyle(.osPrimary).keyboardShortcut(.defaultAction)
                        .disabled(!hasAnswer(q))
                }
            }
        }
        .padding(Space.xxl)
    }

    enum OptionState { case none, correct, wrong }

    private func optionRow(_ text: String, selected: Bool, state: OptionState, action: @escaping () -> Void) -> some View {
        let border: Color = state == .correct ? Theme.success : state == .wrong ? Theme.danger : (selected ? Theme.accent : Theme.border)
        let fill: Color = state == .correct ? Theme.success.opacity(0.1) : state == .wrong ? Theme.danger.opacity(0.1) : (selected ? Theme.accentSoft : Theme.raised)
        return Button(action: action) {
            HStack {
                Text(text).font(Typo.reading).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.leading)
                Spacer()
                if state == .correct { Image(systemName: "checkmark").foregroundStyle(Theme.success) }
                if state == .wrong { Image(systemName: "xmark").foregroundStyle(Theme.danger) }
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(border, lineWidth: selected || state != .none ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hasAnswer(_ q: QuizQuestion) -> Bool {
        let a = answers[q.id] ?? Answer()
        switch q.kind {
        case .multipleChoice: return a.choice != nil
        case .trueFalse: return a.bool != nil
        case .shortAnswer: return !a.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func isCorrect(_ q: QuizQuestion) -> Bool {
        let a = answers[q.id] ?? Answer()
        switch q.kind {
        case .multipleChoice: return a.choice == q.correctIndex
        case .trueFalse: return a.bool == q.correctBool
        case .shortAnswer:
            let given = CardImporter.normalize(a.text)
            return q.correctText.split(separator: "|").map { CardImporter.normalize(String($0)) }.contains(given)
        }
    }

    private func next() {
        checked = false
        if index + 1 < questions.count {
            index += 1
        } else {
            finished = true
            let attempt = QuizAttempt(score: score, total: questions.count)
            context.insert(attempt)
            attempt.quiz = quiz
            do {
                try context.save()
                PostHogSDK.shared.capture("quiz_completed", properties: [
                    "score": score,
                    "total_questions": questions.count,
                    "score_percent": Int((Double(score) / Double(max(1, questions.count)) * 100).rounded()),
                ])
            } catch {}
        }
    }

    private var score: Int { questions.filter(isCorrect).count }

    private func answerText(_ q: QuizQuestion) -> String {
        let a = answers[q.id] ?? Answer()
        switch q.kind {
        case .multipleChoice: return a.choice.flatMap { q.options[safe: $0] } ?? "—"
        case .trueFalse: return a.bool.map { $0 ? "True" : "False" } ?? "—"
        case .shortAnswer: return a.text.isEmpty ? "—" : a.text
        }
    }

    private func correctText(_ q: QuizQuestion) -> String {
        switch q.kind {
        case .multipleChoice: q.options[safe: q.correctIndex] ?? ""
        case .trueFalse: q.correctBool ? "True" : "False"
        case .shortAnswer: q.correctText.replacingOccurrences(of: "|", with: " or ")
        }
    }

    private var results: some View {
        let wrong = questions.filter { !isCorrect($0) }
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(score)/\(questions.count)").font(Typo.displayXL(48))
                    Text("\(Int((Double(score) / Double(max(1, questions.count)) * 100).rounded()))% correct")
                        .font(Typo.title).foregroundStyle(Theme.textSecondary)
                }
                if wrong.isEmpty {
                    Label("Perfect score — every answer was correct.", systemImage: "checkmark.seal.fill")
                        .font(Typo.headline).foregroundStyle(Theme.success)
                } else {
                    SectionLabel("Review incorrect answers")
                    ForEach(wrong) { q in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(q.prompt).font(Typo.headline)
                            Label("Your answer: \(answerText(q))", systemImage: "xmark").font(Typo.body).foregroundStyle(Theme.danger)
                            Label("Correct: \(correctText(q))", systemImage: "checkmark").font(Typo.body).foregroundStyle(Theme.success)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                    }
                }
                HStack {
                    Button("Retake") {
                        answers = [:]; index = 0; finished = false; checked = false
                    }
                    .buttonStyle(.osSecondary)
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(.osPrimary).keyboardShortcut(.defaultAction)
                }
            }
            .padding(Space.xxl)
        }
    }
}
