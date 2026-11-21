import SwiftUI

/// Every animal you've met, plus blurred teasers of the ones still waiting.
struct JournalView: View {
    @Environment(AppStore.self) private var store
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    stats
                    if !store.journalAnimals.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Eyebrow("Animals you've met")
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(store.journalAnimals) { item in
                                    NavigationLink(value: item.animal) {
                                        JournalCard(animal: item.animal, date: item.entry.date,
                                                    passed: store.hasPassedQuiz(item.animal))
                                    }
                                    .buttonStyle(PressableStyle())
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
                                LockedCard(animal: animal)
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
                StatTile(value: "\(store.state.quizPassedIDs.count)", label: "quizzes passed",
                         symbol: "checkmark.seal.fill", tint: .faunaMoss)
                StatTile(value: "\(Set(store.journalAnimals.map { $0.animal.group }).count)", label: "kinds of animal",
                         symbol: "square.grid.2x2.fill", tint: .blue)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

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
                    Text(date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(14)
            }
            .overlay(alignment: .topTrailing) {
                if passed {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.faunaGold)
                        .padding(7)
                        .background(.ultraThinMaterial, in: Circle())
                        .environment(\.colorScheme, .dark)
                        .padding(10)
                        .accessibilityLabel("Quiz passed")
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
            .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(animal.name), met \(date.formatted(date: .abbreviated, time: .omitted))")
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Undiscovered \(animal.group.singular.lowercased())")
    }
}
