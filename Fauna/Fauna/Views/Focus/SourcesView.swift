import SwiftUI

/// Where Fauna's words, photos and maps come from, and the licenses they're used under.
struct SourcesView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                Text("Fauna's articles are adapted and condensed from Wikipedia articles, written by Wikipedia's contributors and licensed under the Creative Commons Attribution-ShareAlike 4.0 license. Changes were made. Fauna's article text is shared under the same license, so you're free to reuse it with credit.")
                    .font(.subheadline)
                Link("Creative Commons BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                Text("Each article links to its original on Wikipedia at the end of the page.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Article text")
            }

            Section {
                Text("Photos come from Wikimedia Commons. Each has its own author and license, shown on the photo and listed here. Fauna only uses freely licensed photos; images that Wikipedia uses under 'fair use' are skipped. Tap a credit to see the photo's page.")
                    .font(.subheadline)
                ForEach(photoAnimals) { animal in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(animal.name).font(.subheadline.weight(.semibold))
                        PhotoCreditLine(animal: animal)
                    }
                }
            } header: {
                Text("Photos")
            } footer: {
                Text("Credits for animals you haven't met yet appear here once you meet them.")
            }

            Section {
                Text("Range maps use Apple Maps imagery, © Apple and its data providers.")
                    .font(.subheadline)
            } header: {
                Text("Maps")
            }

            Section {
                Text("Wikipedia is a trademark of the Wikimedia Foundation. Fauna is an independent app and isn't affiliated with or endorsed by Wikipedia, the Wikimedia Foundation, or the conservation organizations it links to.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sources & Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var photoAnimals: [Animal] {
        store.journalAnimals.map(\.animal).sorted { $0.name < $1.name }
    }
}
