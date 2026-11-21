import SwiftUI

/// Apple-style welcome: what Fauna is, what you'd like to meet, and when to say hello.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var groups: Set<AnimalGroup> = []
    @State private var regions: Set<Region> = []
    @State private var reminderTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: welcome
                case 1: focus
                default: reminder
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.snappy) { step -= 1 }
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("Back")
                    }
                }
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Image("Logo")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .padding(.top, 48)
                        .accessibilityHidden(true)
                    Text("Welcome to Fauna")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .padding(.top, 24)
                    Text("One remarkable animal, every day.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 28) {
                        FeatureRow(symbol: "book.pages.fill", tint: .blue, title: "A Two-Minute Read",
                                   text: "Wikipedia, condensed into something you'll actually finish.")
                        FeatureRow(symbol: "checkmark.seal.fill", tint: .green, title: "Earn the Next One",
                                   text: "Want another? Answer three quick questions to show you read it.")
                        FeatureRow(symbol: "heart.fill", tint: .pink, title: "Help If You're Moved",
                                   text: "Every animal links to the people working to protect it.")
                    }
                    .padding(.top, 44)
                    .padding(.horizontal, 12)
                }
                .padding(.horizontal, 28)
            }
            bottomButton("Continue") { go(to: 1) }
        }
    }

    private var focus: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    VStack(spacing: 8) {
                        Text("What Would You Like to Meet?")
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text("Choose any kinds of animals and places, or none for a surprise from anywhere. You can change this later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                FocusSections(groups: $groups, regions: $regions)
            }
            .listStyle(.insetGrouped)
            let count = store.library.filter { store.matchesFocus($0, groups: groups, regions: regions) }.count
            bottomButton(groups.isEmpty && regions.isEmpty ? "Surprise Me" : "Continue",
                         caption: count == 0 ? "Nothing matches yet; Fauna will pick from everywhere." : "\(count) animals to discover") {
                go(to: 2)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var reminder: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.red)
                        .padding(.top, 56)
                        .accessibilityHidden(true)
                    Text("A Daily Hello")
                        .font(.largeTitle.bold())
                        .padding(.top, 20)
                    Text("Get one notification a day naming the animal that's waiting for you.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                        .padding(.horizontal, 16)

                    // A preview of what the notification will look like.
                    HStack(spacing: 10) {
                        Image("Logo")
                            .resizable()
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text("Meet the Okapi").font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("now").font(.caption).foregroundStyle(.secondary)
                            }
                            Text("The forest giraffe with zebra legs. 2-minute read.")
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                    .padding(.top, 32)
                    .accessibilityHidden(true)

                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.top, 24)
                }
                .padding(.horizontal, 28)
            }
            VStack(spacing: 4) {
                bottomButton("Turn On Notifications") { finish(withReminder: true) }
                Button("Not Now") { finish(withReminder: false) }
                    .padding(.bottom, 8)
            }
        }
    }

    private func bottomButton(_ title: String, caption: String? = nil, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Button(title, action: action)
                .buttonStyle(ProminentPillStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Actions

    private func go(to next: Int) {
        withAnimation(.snappy) { step = next }
    }

    private func finish(withReminder: Bool) {
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
            withAnimation(.smooth(duration: 0.5)) { store.completeOnboarding() }
            await Reminders.reschedule(store)
        }
    }
}

/// The icon-title-description row from Apple's welcome screens.
private struct FeatureRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(tint)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
