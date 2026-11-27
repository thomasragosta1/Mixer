import SwiftUI

/// Every animal you've met, plus blurred teasers of the ones still waiting.
struct JournalView: View {
    @Environment(AppStore.self) private var store
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    @State private var filter = JournalFilter.all

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    stats
                    if !store.journalAnimals.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Eyebrow("Animals you've met")
                            Picker("Show", selection: $filter) {
                                Text("All").tag(JournalFilter.all)
                                Text("To take (\(store.quizzesToTake.count))").tag(JournalFilter.quizToTake)
                                Text("Completed (\(store.quizzesCompleted.count))").tag(JournalFilter.completed)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("journal.filter")
                            if filter == .quizToTake && store.quizzesToTake.isEmpty {
                                emptyNote("You've passed every quiz so far.", symbol: "checkmark.seal.fill")
                            }
                            if filter == .completed && store.quizzesCompleted.isEmpty {
                                emptyNote("Pass an animal's quiz to earn its gold seal.", symbol: "rosette")
                            }
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(shownItems) { item in
                                    if item.animal.id == store.currentAnimal?.id {
                                        // Today's animal lives on Today, where its quiz unlocks the next one.
                                        Button {
                                            store.selectedTab = .today
                                        } label: {
                                            JournalCard(animal: item.animal, date: item.entry.date,
                                                        passed: store.hasPassedQuiz(item.animal), isToday: true)
                                        }
                                        .buttonStyle(PressableStyle())
                                        .accessibilityHint("Opens Today")
                                    } else {
                                        NavigationLink(value: item.animal) {
                                            JournalCard(animal: item.animal, date: item.entry.date,
                                                        passed: store.hasPassedQuiz(item.animal))
                                        }
                                        .buttonStyle(PressableStyle())
                                    }
                                }
                            }
                        }
                    }
                    if !store.undiscovered.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow("Still out there")
                            Text("Read today's animal and pass its quiz to meet another.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.undiscovered) { animal in
                                Button {
                                    store.selectedTab = .today
                                } label: {
                                    LockedCard(animal: animal)
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityHint("Opens Today, where you can unlock your next animal")
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Journal")
            .navigationDestination(for: Animal.self) { AnimalArticleView(animal: $0, mode: .journal) }
        }
    }

    private var shownItems: [JournalItem] {
        switch filter {
        case .all: store.journalAnimals
        case .quizToTake: store.quizzesToTake
        case .completed: store.quizzesCompleted
        }
    }

    private func emptyNote(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    private var stats: some View {
        let met = store.metIDs.count
        let total = store.library.count
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(met)")
                    .font(FaunaFont.display(54))
                    .contentTransition(.numericText())
                Text("of \(total) animals discovered")
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(met), total: Double(max(total, 1)))
                .tint(Color.faunaMoss)
            HStack(spacing: 12) {
                StatTile(value: "\(store.streak)", label: "day streak",
                         symbol: "flame.fill", tint: .orange)
                // Out of the animals met, since those are the quizzes there are to take.
                StatTile(value: "\(store.state.quizPassedIDs.filter(store.metIDs.contains).count)/\(met)", label: "quizzes passed",
                         symbol: "checkmark.seal.fill", tint: .faunaMoss)
                // The seven groups Focus filters by (mammals, birds, fish, insects...), so say so.
                StatTile(value: "\(Set(store.journalAnimals.map { $0.animal.group }).count)/\(AnimalGroup.allCases.count)",
                         label: "groups, like birds or fish",
                         symbol: "square.grid.2x2.fill", tint: .blue)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private enum JournalFilter: Hashable { case all, quizToTake, completed }

private struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct JournalCard: View {
    let animal: Animal
    let date: Date
    let passed: Bool
    var isToday = false

    var body: some View {
        AnimalPhoto(animal: animal, size: .card)
            .aspectRatio(0.78, contentMode: .fit)
            .overlay {
                LinearGradient(colors: [.clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(animal.name)
                        .font(FaunaFont.display(19))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(isToday ? "Today · tap to read" : date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption.weight(isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? Color.faunaGold : .white.opacity(0.75))
                }
                .padding(14)
            }
            .overlay(alignment: .topTrailing) {
                if passed {
                    PassedSeal()
                        .padding(9)
                }
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: animal.group.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(animal.group.color, in: Circle())
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                // A gold frame for every quiz passed, so a full journal glitters.
                if passed {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(PassedSeal.gold, lineWidth: 2.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(animal.name), met \(date.formatted(date: .abbreviated, time: .omitted))\(passed ? ", quiz passed" : "")")
    }
}

/// The gold seal on a journal card whose quiz has been passed: a glowing medal with a white
/// check and a sparkle, which pops in when it first appears.
struct PassedSeal: View {
    static let gold = LinearGradient(
        colors: [Color(red: 1.0, green: 0.90, blue: 0.55), Color.faunaGold, Color(red: 0.80, green: 0.55, blue: 0.12)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Image(systemName: "seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(Self.gold)
                .shadow(color: Color.faunaGold.opacity(0.8), radius: 6)
            Image(systemName: "seal")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
                .shadow(color: Color(red: 0.55, green: 0.35, blue: 0.0).opacity(0.6), radius: 1, y: 1)
            Image(systemName: "sparkle")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: 15, y: -15)
                .opacity(shown ? 1 : 0)
        }
        .scaleEffect(shown || reduceMotion ? 1 : 0.4)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.5)) { shown = true }
        }
        .accessibilityHidden(true)
    }
}

private struct LockedCard: View {
    let animal: Animal

    var body: some View {
        AnimalPhoto(animal: animal, size: .card)
            .blur(radius: 22)
            .saturation(0.7)
            .aspectRatio(0.78, contentMode: .fit)
            .overlay(Color.black.opacity(0.25))
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                    Label(animal.group.singular, systemImage: animal.group.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(animal.regions.first?.shortTitle ?? "")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .environment(\.colorScheme, .dark)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Undiscovered \(animal.group.singular.lowercased())")
    }
}
