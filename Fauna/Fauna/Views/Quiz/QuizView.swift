import SwiftUI

/// Up to three multiple-choice questions about the animal just read. All must be right to
/// unlock the next animal; a miss explains the answer and offers another go.
struct QuizView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let animal: Animal

    private struct Item: Identifiable {
        let id = UUID()
        let prompt: String
        let choices: [String]
        let correct: Int
        let explanation: String
    }

    private enum Phase: Equatable { case asking, results }

    @State private var items: [Item] = []
    @State private var index = 0
    @State private var picked: Int?
    @State private var correctCount = 0
    @State private var phase: Phase = .asking
    @State private var shake = 0
    @State private var unlocked: Animal?

    private var passed: Bool { correctCount == items.count && !items.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                switch phase {
                case .asking:
                    if items.indices.contains(index) {
                        question(items[index])
                            .id(items[index].id)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                case .results:
                    results
                        .transition(.opacity)
                }
            }
            .navigationTitle(phase == .results ? "" : "Question \(index + 1) of \(items.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if phase == .asking {
                    ProgressView(value: Double(index + (picked == nil ? 0 : 1)), total: Double(max(items.count, 1)))
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                        .animation(.smooth, value: picked)
                }
            }
        }
        .onAppear(perform: start)
    }

    // MARK: Question

    private func question(_ item: Item) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        AnimalPhoto(animal: animal, size: .card)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        Text(animal.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 16)

                    Text(item.prompt)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 20)

                    VStack(spacing: 0) {
                        ForEach(item.choices.indices, id: \.self) { i in
                            choiceRow(item, i)
                            if i < item.choices.count - 1 {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .modifier(Shake(animatableData: CGFloat(shake)))

                    if let picked {
                        feedback(item, wasRight: picked == item.correct)
                            .padding(.top, 16)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            if picked != nil {
                Button(index + 1 < items.count ? "Next Question" : "See Results", action: advance)
                    .buttonStyle(ProminentPillStyle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func choiceRow(_ item: Item, _ i: Int) -> some View {
        let isPicked = picked == i
        let isCorrect = i == item.correct
        let revealed = picked != nil
        let symbol: String = {
            guard revealed else { return "circle" }
            if isCorrect { return "checkmark.circle.fill" }
            return isPicked ? "xmark.circle.fill" : "circle"
        }()
        let tint: Color = !revealed ? Color(.tertiaryLabel) : (isCorrect ? .green : (isPicked ? .red : Color(.tertiaryLabel)))

        return Button {
            choose(i, in: item)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24)
                Text(item.choices[i])
                    .foregroundStyle(revealed && !isCorrect && !isPicked ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(revealed)
        .accessibilityLabel(item.choices[i])
        .accessibilityValue(!revealed ? "" : (isCorrect ? "Correct answer" : (isPicked ? "Your answer, incorrect" : "")))
    }

    private func feedback(_ item: Item, wasRight: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: wasRight ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.title3)
                .foregroundStyle(wasRight ? .green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(wasRight ? "Correct" : "Not Quite")
                    .font(.headline)
                Text(item.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if passed { success } else { retry }
    }

    private var success: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: phase)
                        .padding(.top, 56)
                    Text("\(items.count) for \(items.count)")
                        .font(.largeTitle.bold())
                    Text(unlocked == nil ? "You really read it. That's every animal for now." : "You really read it. Your next animal is ready.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let unlocked {
                        HStack(spacing: 14) {
                            AnimalPhoto(animal: unlocked, size: .card)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(unlocked.name).font(.headline)
                                Text(unlocked.tagline)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 24)
            }
            Button(unlocked.map { "Meet the \($0.name)" } ?? "Done") { dismiss() }
                .buttonStyle(ProminentPillStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    private var retry: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.orange)
                        .symbolEffect(.bounce, value: phase)
                        .padding(.top, 56)
                    Text("\(correctCount) of \(items.count) Correct")
                        .font(.largeTitle.bold())
                    Text("Every answer needs to be right to unlock the next animal. Everything you need is in the article.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
            }
            VStack(spacing: 8) {
                Button("Read It Again") { dismiss() }
                    .buttonStyle(ProminentPillStyle())
                Button("Try the Questions Again") {
                    withAnimation(.smooth) { start() }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: Logic

    private func start() {
        items = animal.quiz.prefix(3).shuffled().map { q in
            let order = q.choices.indices.shuffled()
            return Item(prompt: q.prompt,
                        choices: order.map { q.choices[$0] },
                        correct: order.firstIndex(of: 0) ?? 0,
                        explanation: q.explanation)
        }
        index = 0
        picked = nil
        correctCount = 0
        unlocked = nil
        phase = .asking
    }

    private func choose(_ i: Int, in item: Item) {
        guard picked == nil else { return }
        withAnimation(.snappy) { picked = i }
        if i == item.correct {
            correctCount += 1
            Haptics.success()
        } else {
            Haptics.error()
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
        }
    }

    private func advance() {
        if index + 1 < items.count {
            withAnimation(.snappy) {
                index += 1
                picked = nil
            }
        } else {
            if passed {
                let anywhere = !store.canUnlockInFocus
                unlocked = store.unlockNext(for: animal, allowOutsideFocus: anywhere)
                Task { await Reminders.reschedule(store) }
            }
            withAnimation(.smooth) { phase = .results }
        }
    }
}

/// Horizontal wobble for a wrong answer.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
