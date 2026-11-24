import SwiftUI

/// Up to three multiple-choice questions about the animal just read. All must be right to
/// unlock the next animal; a miss explains the answer and offers another go.
struct QuizView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let animal: Animal
    /// Practice quizzes (from the Journal) test you without unlocking a new animal.
    var practice = false

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
    @State private var revealed = false

    private var passed: Bool { correctCount == items.count && !items.isEmpty }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                switch phase {
                case .asking:
                    if items.indices.contains(index) {
                        ScrollIfNeeded { question(items[index]) }
                            .id(items[index].id)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                case .results:
                    ScrollIfNeeded { results }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: start)
    }

    // MARK: Chrome

    private var backdrop: some View {
        ZStack {
            AnimalPhoto(animal: animal, size: .card)
                .blur(radius: 40)
                .scaleEffect(1.3)
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")

            HStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    Capsule()
                        .fill(i < index || phase == .results ? Color.faunaGold :
                                (i == index ? Color.white : Color.white.opacity(0.22)))
                        .frame(height: 5)
                }
            }
            .animation(.smooth, value: index)
            .accessibilityHidden(true)

            Text(phase == .results ? "Done" : "\(index + 1) of \(items.count)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    // MARK: Question

    private func question(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 20)
            Eyebrow("About the \(animal.name)", color: .faunaGold)
                .padding(.bottom, 12)
            Text(item.prompt)
                .font(FaunaFont.display(30))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 28)

            VStack(spacing: 12) {
                ForEach(item.choices.indices, id: \.self) { i in
                    choiceButton(item, i)
                }
            }
            .modifier(Shake(animatableData: CGFloat(shake)))

            if let picked {
                feedback(item, wasRight: picked == item.correct)
                    .padding(.top, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    private func choiceButton(_ item: Item, _ i: Int) -> some View {
        let letter = ["A", "B", "C", "D", "E"][min(i, 4)]
        let isPicked = picked == i
        let isCorrect = i == item.correct
        let revealedState: Color? = picked == nil ? nil : (isCorrect ? .green : (isPicked ? .red : nil))

        return Button {
            choose(i, in: item)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(revealedState.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.white.opacity(0.12)))
                        .frame(width: 34, height: 34)
                    if picked != nil && (isCorrect || isPicked) {
                        Image(systemName: isCorrect ? "checkmark" : "xmark")
                            .font(.system(size: 14, weight: .heavy))
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text(letter).font(.system(.subheadline, design: .rounded).weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                Text(item.choices[i])
                    .font(.system(.body, design: .default).weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill((revealedState ?? .clear).opacity(0.22))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder((revealedState ?? .white).opacity(revealedState == nil ? 0.12 : 0.8), lineWidth: revealedState == nil ? 1 : 2)
            }
            .opacity(picked != nil && !isCorrect && !isPicked ? 0.45 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(picked != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: picked)
        .accessibilityLabel(item.choices[i])
        .accessibilityValue(picked == nil ? "" : (isCorrect ? "Correct answer" : (isPicked ? "Your answer, incorrect" : "")))
        // For UI tests; identifiers are never spoken by VoiceOver.
        .accessibilityIdentifier(isCorrect ? "quiz.choice.correct" : "quiz.choice.wrong")
    }

    private func feedback(_ item: Item, wasRight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: wasRight ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(wasRight ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(wasRight ? "Exactly right." : "Not quite.")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(item.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: advance) {
                Text(index + 1 < items.count ? "Next question" : "See results")
            }
            .buttonStyle(ProminentPillStyle(tint: wasRight ? .faunaMoss : .orange))
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if passed {
            success
        } else {
            retry
        }
    }

    private var success: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                ForEach(0..<3) { ring in
                    Circle()
                        .strokeBorder(Color.faunaGold.opacity(0.35 - Double(ring) * 0.1), lineWidth: 1.5)
                        .frame(width: 120 + CGFloat(ring) * 44, height: 120 + CGFloat(ring) * 44)
                        .scaleEffect(revealed ? 1 : 0.6)
                        .opacity(revealed ? 1 : 0)
                        .animation(.spring(response: 0.7, dampingFraction: 0.6).delay(Double(ring) * 0.08), value: revealed)
                }
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(Color.faunaGold)
                    .symbolEffect(.bounce, value: revealed)
            }
            .frame(height: 220)

            VStack(spacing: 8) {
                Text("\(items.count) for \(items.count). You really read it.")
                    .font(FaunaFont.display(28))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(successMessage)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
            }

            if let unlocked {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        AnimalPhoto(animal: unlocked, size: .card)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Meet the \(unlocked.name)")
                                .font(FaunaFont.display(20))
                                .foregroundStyle(.white)
                            Text(unlocked.tagline)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(2)
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color.faunaGold)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 30)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.35), value: revealed)
            } else {
                Button(practice ? "Done" : "Back to today") { dismiss() }
                    .buttonStyle(ProminentPillStyle(tint: .faunaMoss))
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear { revealed = true }
    }

    private var retry: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "book.and.wrench.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, value: phase)
            VStack(spacing: 10) {
                Text("\(correctCount) of \(items.count). So close.")
                    .font(FaunaFont.display(30))
                    .foregroundStyle(.white)
                Text("Every answer needs to be right to unlock the next animal. Everything you need is in the article.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                Button("Read it again") { dismiss() }
                    .buttonStyle(ProminentPillStyle(tint: .faunaMoss))
                Button("Try the questions again") {
                    withAnimation(.smooth) { start() }
                }
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.vertical, 8)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: Logic

    private func start() {
        items = animal.quiz.prefix(3).shuffled().map { q in
            let order = q.choices.indices.shuffled()
            return Item(prompt: store.measured(q.prompt),
                        choices: order.map { store.measured(q.choices[$0]) },
                        correct: order.firstIndex(of: 0) ?? 0,
                        explanation: store.measured(q.explanation))
        }
        index = 0
        picked = nil
        correctCount = 0
        unlocked = nil
        revealed = false
        phase = .asking
    }

    private func choose(_ i: Int, in item: Item) {
        guard picked == nil else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { picked = i }
        if i == item.correct {
            correctCount += 1
            Haptics.success()
        } else {
            Haptics.error()
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
        }
    }

    private var successMessage: String {
        if practice { return "The \(animal.name) is yours." }
        guard unlocked != nil else { return "You've discovered every animal in Fauna. Come back tomorrow." }
        let today = store.state.todayChain.count
        return "Your next animal is ready. That's \(today) today, and you can keep going as long as you like."
    }

    private func advance() {
        Haptics.tap()
        if index + 1 < items.count {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                index += 1
                picked = nil
            }
        } else {
            if passed && practice {
                store.markQuizPassed(animal)
                Haptics.success()
            } else if passed {
                let anywhere = !store.canUnlockInFocus
                unlocked = store.unlockNext(for: animal, allowOutsideFocus: anywhere)
                Task { await Reminders.reschedule(store) }
                Haptics.success()
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { phase = .results }
        }
    }
}

/// Horizontal wobble for a wrong answer.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 9 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Lays content out to fill the screen, but scrolls when it can't fit, as with the largest
/// accessibility text sizes; otherwise the quiz's buttons end up off screen and unreachable.
private struct ScrollIfNeeded<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollIndicators(.hidden)
        }
    }
}
