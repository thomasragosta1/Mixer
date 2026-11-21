import SwiftUI

/// Three quiet steps: what Fauna is, what you'd like to learn about, and when to say hello.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var groups: Set<AnimalGroup> = []
    @State private var regions: Set<Region> = []
    @State private var reminderTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    @State private var appeared = false

    var body: some View {
        ZStack {
            DriftingBackdrop()
            VStack(spacing: 0) {
                pageDots
                    .padding(.top, 12)
                Group {
                    switch step {
                    case 0: welcome
                    case 1: focus
                    default: reminder
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { appeared = true } }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i == step ? Color.white : Color.white.opacity(0.25))
                    .frame(width: i == step ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
        .accessibilityHidden(true)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("Logo")
                .resizable()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, 20)
                .accessibilityHidden(true)
            Text("Fauna")
                .font(FaunaFont.display(64))
                .foregroundStyle(.white)
            Text("One remarkable animal, every day.")
                .font(.system(.title3, design: .serif).italic())
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 18) {
                PromiseRow(symbol: "book.pages.fill", title: "A two-minute read",
                        text: "Wikipedia, condensed into something you'll actually finish.")
                PromiseRow(symbol: "checkmark.seal.fill", title: "Earn the next one",
                        text: "Want another? Answer three quick questions to prove you read it.")
                PromiseRow(symbol: "heart.fill", title: "Help if you're moved",
                        text: "Every animal links to the people working to protect it.")
            }
            .padding(.top, 36)
            .padding(.horizontal, 32)
            Spacer()
            Button("Get started") { go(to: 1) }
                .buttonStyle(ProminentPillStyle(tint: .faunaMoss))
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What would you like to meet?")
                        .font(FaunaFont.display(36))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pick as many as you like, or none for a surprise from anywhere. You can change this any time.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    FocusPicker(groups: $groups, regions: $regions, onDark: true)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            VStack(spacing: 10) {
                let count = store.library.filter { store.matchesFocus($0, groups: groups, regions: regions) }.count
                Text(count == 0 ? "Nothing matches yet; we'll surprise you." : "\(count) animals to discover")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
                    .animation(.smooth, value: count)
                Button(groups.isEmpty && regions.isEmpty ? "Surprise me" : "Continue") { go(to: 2) }
                    .buttonStyle(ProminentPillStyle(tint: .faunaMoss))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private var reminder: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 78)
                HStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("FAUNA").font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            Text("now").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                        Text("Meet the Okapi").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text("The forest giraffe with zebra legs. 2-minute read.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.horizontal, 28)
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .accessibilityHidden(true)

            Text("A daily hello")
                .font(FaunaFont.display(36))
                .foregroundStyle(.white)
                .padding(.top, 40)
            Text("We'll tell you which animal is waiting each morning. One notification a day, never more.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 8)
            DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 150)
                .clipped()
                .padding(.top, 12)
            Spacer()
            VStack(spacing: 12) {
                Button("Remind me daily") { finish(withReminder: true) }
                    .buttonStyle(ProminentPillStyle(tint: .faunaMoss))
                Button("Not now") { finish(withReminder: false) }
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.vertical, 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    // MARK: Actions

    private func go(to next: Int) {
        Haptics.tap()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) { step = next }
    }

    private func finish(withReminder: Bool) {
        Haptics.success()
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        store.state.reminderHour = c.hour ?? 8
        store.state.reminderMinute = c.minute ?? 0
        store.state.reminderEnabled = withReminder
        store.setFocus(groups: groups, regions: regions)
        Task {
            if withReminder {
                let granted = await Reminders.requestAuthorization()
                if !granted { store.state.reminderEnabled = false }
            }
            withAnimation(.smooth(duration: 0.7)) { store.completeOnboarding() }
            await Reminders.reschedule(store)
        }
    }
}

private struct PromiseRow: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.faunaGold)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Deep forest gradient with animal silhouettes drifting slowly upward.
struct DriftingBackdrop: View {
    private struct Mote {
        let symbol: String
        let x: Double, speed: Double, size: Double, phase: Double, spin: Double
    }

    private let motes: [Mote] = {
        var rng = SystemRandomNumberGenerator()
        let symbols = AnimalGroup.allCases.map(\.symbol) + ["leaf.fill", "tortoise.fill", "hare.fill", "ant.fill"]
        return (0..<22).map { i in
            Mote(symbol: symbols[i % symbols.count],
                 x: Double.random(in: 0...1, using: &rng),
                 speed: Double.random(in: 0.012...0.03, using: &rng),
                 size: Double.random(in: 16...38, using: &rng),
                 phase: Double.random(in: 0...1, using: &rng),
                 spin: Double.random(in: -20...20, using: &rng))
        }
    }()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.faunaInk
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    ForEach(motes.indices, id: \.self) { i in
                        let m = motes[i]
                        let progress = (m.phase + t * m.speed).truncatingRemainder(dividingBy: 1)
                        Image(systemName: m.symbol)
                            .font(.system(size: m.size))
                            .foregroundStyle(.white.opacity(0.07 + 0.05 * sin(progress * .pi)))
                            .rotationEffect(.degrees(m.spin * sin(t * 0.3 + m.phase * 6)))
                            .position(x: geo.size.width * (m.x + 0.04 * sin(t * 0.4 + m.phase * 10)),
                                      y: geo.size.height * (1.1 - progress * 1.2))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
