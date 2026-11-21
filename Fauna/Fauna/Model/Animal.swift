import Foundation

/// One animal in the library. Everything a reader sees comes from `animals.json`.
struct Animal: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let scientificName: String
    let wikipediaTitle: String
    let group: AnimalGroup
    let regions: [Region]
    let range: String
    let status: ConservationStatus
    let coordinate: Coordinate
    let mapSpan: Double
    let tagline: String
    let lede: String
    let home: String
    let life: String
    let remarkable: String
    let outlook: String
    /// Longer-read sections; optional so older content still decodes.
    let anatomy: String?
    let family: String?
    let people: String?
    let didYouKnow: String
    let facts: [Fact]
    let quiz: [QuizQuestion]
    let charities: [Charity]

    var wikipediaURL: URL {
        let path = wikipediaTitle.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? wikipediaTitle
        return URL(string: "https://en.wikipedia.org/wiki/\(path)")!
    }

    /// Reading time for the article body, rounded up to whole minutes.
    var readingMinutes: Int {
        let words = [lede, home, life, remarkable, outlook, didYouKnow, anatomy ?? "", family ?? "", people ?? ""]
            .reduce(0) { $0 + $1.split(separator: " ").count }
        return max(1, Int((Double(words) / 220).rounded(.up)))
    }
}

struct Coordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

struct Fact: Codable, Hashable {
    let label: String
    let value: String

    var symbol: String {
        let l = label.lowercased()
        if l.contains("weight") { return "scalemass.fill" }
        if l.contains("life") || l.contains("generation") { return "hourglass" }
        if l.contains("diet") { return "fork.knife" }
        if l.contains("wing") { return "arrow.left.and.right" }
        if l.contains("height") { return "arrow.up.and.down" }
        if l.contains("speed") { return "gauge.with.dots.needle.67percent" }
        if l.contains("colony") { return "person.3.fill" }
        if l.contains("color") { return "eye.fill" }
        if l.contains("dive") { return "arrow.down.to.line" }
        if l.contains("active") { return "sun.max.fill" }
        if l.contains("teeth") { return "mouth.fill" }
        return "ruler.fill"
    }
}

struct QuizQuestion: Codable, Hashable {
    let prompt: String
    /// The first choice is the correct one; the quiz shuffles them for display.
    let choices: [String]
    let explanation: String
}

struct Charity: Codable, Hashable, Identifiable {
    let name: String
    let url: URL
    let blurb: String
    var id: String { name }

    var host: String {
        (url.host() ?? url.absoluteString).replacingOccurrences(of: "www.", with: "")
    }
}

enum AnimalGroup: String, Codable, CaseIterable, Identifiable {
    case mammal, bird, reptile, amphibian, fish, insect, marineInvertebrate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mammal: "Mammals"
        case .bird: "Birds"
        case .reptile: "Reptiles"
        case .amphibian: "Amphibians"
        case .fish: "Fish"
        case .insect: "Insects & Bugs"
        case .marineInvertebrate: "Sea Invertebrates"
        }
    }

    var singular: String {
        switch self {
        case .mammal: "Mammal"
        case .bird: "Bird"
        case .reptile: "Reptile"
        case .amphibian: "Amphibian"
        case .fish: "Fish"
        case .insect: "Insect"
        case .marineInvertebrate: "Sea invertebrate"
        }
    }

    var symbol: String {
        switch self {
        case .mammal: "pawprint.fill"
        case .bird: "bird.fill"
        case .reptile: "lizard.fill"
        case .amphibian: "drop.fill"
        case .fish: "fish.fill"
        case .insect: "ladybug.fill"
        case .marineInvertebrate: "water.waves"
        }
    }
}

enum Region: String, Codable, CaseIterable, Identifiable {
    case arctic, naEast, naWest, centralAmerica, southAmerica, europe, africa, asia, oceania, antarctica, openOcean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arctic: "Arctic"
        case .naEast: "Eastern North America"
        case .naWest: "Western North America"
        case .centralAmerica: "Central America & Mexico"
        case .southAmerica: "South America"
        case .europe: "Europe"
        case .africa: "Africa"
        case .asia: "Asia"
        case .oceania: "Australia & Oceania"
        case .antarctica: "Antarctica"
        case .openOcean: "Open Ocean"
        }
    }

    var shortTitle: String {
        switch self {
        case .naEast: "E. North America"
        case .naWest: "W. North America"
        case .centralAmerica: "Central America"
        case .oceania: "Oceania"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .arctic: "snowflake"
        case .naEast, .naWest, .centralAmerica, .southAmerica: "globe.americas.fill"
        case .europe, .africa: "globe.europe.africa.fill"
        case .asia, .oceania: "globe.asia.australia.fill"
        case .antarctica: "mountain.2.fill"
        case .openOcean: "water.waves"
        }
    }
}

/// IUCN Red List categories.
enum ConservationStatus: String, Codable, CaseIterable {
    case LC, NT, VU, EN, CR, EW, EX, DD, NE

    var title: String {
        switch self {
        case .LC: "Least Concern"
        case .NT: "Near Threatened"
        case .VU: "Vulnerable"
        case .EN: "Endangered"
        case .CR: "Critically Endangered"
        case .EW: "Extinct in the Wild"
        case .EX: "Extinct"
        case .DD: "Data Deficient"
        case .NE: "Not Evaluated"
        }
    }

    /// Position on the seven-step scale from Least Concern to Extinct; nil when unassessed.
    var scaleIndex: Int? {
        switch self {
        case .LC: 0
        case .NT: 1
        case .VU: 2
        case .EN: 3
        case .CR: 4
        case .EW: 5
        case .EX: 6
        case .DD, .NE: nil
        }
    }

    static let scale: [ConservationStatus] = [.LC, .NT, .VU, .EN, .CR, .EW, .EX]

    var isThreatened: Bool { [.VU, .EN, .CR].contains(self) }
}

enum AnimalLibrary {
    static func load(bundle: Bundle = .main) -> [Animal] {
        guard let url = bundle.url(forResource: "animals", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let animals = try? JSONDecoder().decode([Animal].self, from: data) else {
            assertionFailure("animals.json missing or invalid")
            return []
        }
        return animals
    }
}
