import SwiftUI

/// Favourite animals, saved with the bookmark at the top left of any article.
struct BookmarksView: View {
    @Environment(AppStore.self) private var store
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if store.bookmarkedAnimals.isEmpty {
                    ContentUnavailableView {
                        Label("No bookmarks yet", systemImage: "bookmark")
                    } description: {
                        Text("Tap the bookmark at the top left of any article to keep your favourite animals here.")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.bookmarkedAnimals) { animal in
                                NavigationLink(value: animal) {
                                    BookmarkCard(animal: animal)
                                }
                                .buttonStyle(PressableStyle())
                                .contextMenu {
                                    Button(role: .destructive) {
                                        withAnimation(.smooth) { store.toggleBookmark(animal) }
                                    } label: {
                                        Label("Remove bookmark", systemImage: "bookmark.slash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Bookmarks")
            .navigationDestination(for: Animal.self) { AnimalArticleView(animal: $0, mode: .journal) }
        }
    }
}

private struct BookmarkCard: View {
    let animal: Animal

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
                    Text(animal.group.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(14)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.faunaGold)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(animal.name), bookmarked")
    }
}
