import XCTest
@testable import Fauna

/// The bundled library: every animal must be complete, consistent and safe to show.
final class ContentTests: XCTestCase {
    private static let animals = AnimalLibrary.load()
    private var animals: [Animal] { Self.animals }

    func testLibraryLoadsAllAnimals() {
        XCTAssertEqual(animals.count, 68)
    }

    func testIDsAreUnique() {
        XCTAssertEqual(Set(animals.map(\.id)).count, animals.count)
    }

    func testWikipediaTitlesAreUnique() {
        XCTAssertEqual(Set(animals.map(\.wikipediaTitle)).count, animals.count)
    }

    func testNamesAreUnique() {
        XCTAssertEqual(Set(animals.map { $0.name.lowercased() }).count, animals.count)
    }

    func testEveryAnimalHasThreeQuestions() {
        for a in animals { XCTAssertEqual(a.quiz.count, 3, a.id) }
    }

    func testEveryQuestionHasFourDistinctNonEmptyChoices() {
        for a in animals {
            for q in a.quiz {
                XCTAssertEqual(q.choices.count, 4, "\(a.id): \(q.prompt)")
                XCTAssertEqual(Set(q.choices.map { $0.lowercased() }).count, q.choices.count, "\(a.id): \(q.prompt)")
                XCTAssertFalse(q.choices.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }, a.id)
            }
        }
    }

    func testEveryQuestionIsAQuestionWithAnExplanation() {
        for a in animals {
            for q in a.quiz {
                XCTAssertTrue(q.prompt.hasSuffix("?"), "\(a.id): \(q.prompt)")
                XCTAssertGreaterThan(q.explanation.count, 10, "\(a.id): \(q.prompt)")
            }
        }
    }

    func testQuestionsWithinAnAnimalAreDifferent() {
        for a in animals { XCTAssertEqual(Set(a.quiz.map(\.prompt)).count, a.quiz.count, a.id) }
    }

    func testEveryAnimalHasARegionAndValidCoordinates() {
        for a in animals {
            XCTAssertFalse(a.regions.isEmpty, a.id)
            XCTAssertTrue((-90...90).contains(a.coordinate.latitude), a.id)
            XCTAssertTrue((-180...180).contains(a.coordinate.longitude), a.id)
            XCTAssertGreaterThan(a.mapSpan, 0, a.id)
            XCTAssertLessThanOrEqual(a.mapSpan, 180, a.id)
        }
    }

    func testEveryAnimalHasFourFacts() {
        for a in animals {
            XCTAssertEqual(a.facts.count, 4, a.id)
            for f in a.facts {
                XCTAssertFalse(f.label.isEmpty, a.id)
                XCTAssertFalse(f.value.isEmpty, a.id)
            }
        }
    }

    func testEveryAnimalHasASecureCharityLink() {
        for a in animals {
            XCTAssertFalse(a.charities.isEmpty, a.id)
            for c in a.charities {
                XCTAssertEqual(c.url.scheme, "https", "\(a.id): \(c.url)")
                XCTAssertNotNil(c.url.host(), a.id)
                XCTAssertFalse(c.blurb.isEmpty, a.id)
            }
        }
    }

    func testEveryLongReadSectionIsPresent() {
        for a in animals {
            for (name, text) in [("anatomy", a.anatomy), ("family", a.family), ("people", a.people), ("relatives", a.relatives)] {
                XCTAssertFalse((text ?? "").isEmpty, "\(a.id) is missing \(name)")
            }
            for text in [a.lede, a.home, a.life, a.remarkable, a.outlook, a.didYouKnow, a.tagline, a.range] {
                XCTAssertFalse(text.isEmpty, a.id)
            }
        }
    }

    func testReadingTimeIsAboutFourMinutes() {
        for a in animals { XCTAssertTrue((3...6).contains(a.readingMinutes), "\(a.id): \(a.readingMinutes) min") }
    }

    func testParagraphsAreNeverEmptyOrDoubleSpaced() {
        for a in animals {
            for text in [a.lede, a.home, a.life, a.remarkable, a.outlook, a.anatomy ?? "", a.family ?? "", a.people ?? "", a.relatives ?? ""] {
                XCTAssertFalse(text.contains("\n\n\n"), a.id)
                XCTAssertFalse(text.contains("  "), a.id)
                for p in text.components(separatedBy: "\n\n") {
                    XCTAssertFalse(p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, a.id)
                }
            }
        }
    }

    func testEveryKindOfAnimalIsRepresented() {
        let groups = Set(animals.map(\.group))
        for g in AnimalGroup.allCases { XCTAssertTrue(groups.contains(g), g.rawValue) }
    }

    func testEveryPlaceIsRepresented() {
        let regions = Set(animals.flatMap(\.regions))
        for r in Region.allCases { XCTAssertTrue(regions.contains(r), r.rawValue) }
    }

    func testBugsInEasternCanadaExist() {
        let bugs = animals.filter { $0.group == .insect && $0.regions.contains(.naEast) }
        XCTAssertGreaterThanOrEqual(bugs.count, 3)
    }

    func testWikipediaURLsAreWellFormed() {
        for a in animals {
            let url = a.wikipediaURL
            XCTAssertEqual(url.host(), "en.wikipedia.org", a.id)
            XCTAssertFalse(url.absoluteString.contains(" "), a.id)
            XCTAssertTrue(url.path().hasPrefix("/wiki/"), a.id)
        }
    }

    func testAnimalRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(animals)
        let decoded = try JSONDecoder().decode([Animal].self, from: data)
        XCTAssertEqual(decoded, animals)
    }

    func testEveryAnimalHasABundledFreelyLicensedPhoto() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "photos", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]])
        for a in animals {
            let entry = try XCTUnwrap(json[a.wikipediaTitle], "\(a.id) has no bundled photo")
            let original = try XCTUnwrap(entry["original"] as? String)
            XCTAssertTrue(original.hasPrefix("https://upload.wikimedia.org/wikipedia/commons/"), a.id)
            let credit = try XCTUnwrap(entry["credit"] as? [String: Any])
            let license = (credit["license"] as? String ?? "").lowercased()
            XCTAssertFalse(license.isEmpty, a.id)
            XCTAssertFalse(license.contains("fair use") || license.contains("non-free"), a.id)
        }
    }
}

/// Small model helpers.
final class ModelTests: XCTestCase {
    func testFactSymbols() {
        XCTAssertEqual(Fact(label: "Weight", value: "1 kg").symbol, "scalemass.fill")
        XCTAssertEqual(Fact(label: "Lifespan", value: "5 years").symbol, "hourglass")
        XCTAssertEqual(Fact(label: "Diet", value: "Bamboo").symbol, "fork.knife")
        XCTAssertEqual(Fact(label: "Wingspan", value: "3 m").symbol, "arrow.left.and.right")
        XCTAssertEqual(Fact(label: "Length", value: "1 m").symbol, "ruler.fill")
    }

    func testCharityHostDropsWWW() {
        let c = Charity(name: "Red Panda Network", url: URL(string: "https://www.redpandanetwork.org/donate")!, blurb: "x")
        XCTAssertEqual(c.host, "redpandanetwork.org")
    }

    func testRedListScaleOrder() {
        for (i, s) in ConservationStatus.scale.enumerated() { XCTAssertEqual(s.scaleIndex, i) }
        XCTAssertNil(ConservationStatus.DD.scaleIndex)
        XCTAssertNil(ConservationStatus.NE.scaleIndex)
    }

    func testThreatenedCategories() {
        XCTAssertEqual(Set(ConservationStatus.allCases.filter(\.isThreatened)), [.VU, .EN, .CR])
    }

    func testGroupAndRegionTitlesAreUnique() {
        XCTAssertEqual(Set(AnimalGroup.allCases.map(\.title)).count, AnimalGroup.allCases.count)
        XCTAssertEqual(Set(Region.allCases.map(\.title)).count, Region.allCases.count)
        XCTAssertEqual(Set(Region.allCases.map(\.shortTitle)).count, Region.allCases.count)
    }

    func testPhotoCreditLine() {
        let page = URL(string: "https://commons.wikimedia.org/wiki/File:X.jpg")!
        XCTAssertEqual(PhotoCredit(file: "X.jpg", author: "Jane Smith", license: "CC BY-SA 4.0", licenseURL: nil, pageURL: page).line,
                       "Photo: Jane Smith, CC BY-SA 4.0")
        XCTAssertEqual(PhotoCredit(file: "X.jpg", author: "", license: "", licenseURL: nil, pageURL: page).line,
                       "Photo: Wikimedia Commons")
    }
}
