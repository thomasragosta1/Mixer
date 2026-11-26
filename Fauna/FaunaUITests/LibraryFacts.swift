import Foundation

/// Counts from the real animals.json, so UI tests keep working as the library grows. The
/// simulator can read the source tree, which sits next to this file.
enum LibraryFacts {
    struct Entry: Decodable { let name: String; let group: String; let regions: [String] }

    static let animals: [Entry] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fauna/Resources/animals.json")
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }()

    static var total: Int { animals.count }

    static func count(group: String? = nil, region: String? = nil) -> Int {
        animals.filter { (group == nil || $0.group == group) && (region == nil || $0.regions.contains(region!)) }.count
    }

    static func names(group: String, region: String) -> [String] {
        animals.filter { $0.group == group && $0.regions.contains(region) }.map(\.name)
    }

    /// Chip titles as the Focus picker shows them.
    static let groupTitles = ["mammal": "Mammals", "bird": "Birds", "reptile": "Reptiles", "amphibian": "Amphibians",
                              "fish": "Fish", "insect": "Insects & Bugs", "marineInvertebrate": "Sea Invertebrates"]
    static let regionTitles = ["arctic": "Arctic", "naEast": "Eastern North America", "naWest": "Western North America",
                               "centralAmerica": "Central America & Mexico", "southAmerica": "South America",
                               "europe": "Europe", "africa": "Africa", "asia": "Asia", "oceania": "Australia & Oceania",
                               "antarctica": "Antarctica", "openOcean": "Open Ocean"]

    /// A kind-and-place pair with no animals at all, for testing the empty state.
    static var emptyCombination: (group: String, region: String)? {
        for g in groupTitles.keys.sorted() {
            for r in regionTitles.keys.sorted() where count(group: g, region: r) == 0 { return (g, r) }
        }
        return nil
    }
}
