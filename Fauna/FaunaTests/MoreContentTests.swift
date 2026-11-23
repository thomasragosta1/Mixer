import XCTest
import UIKit
@testable import Fauna

/// Editorial and asset checks on the library.
final class MoreContentTests: XCTestCase {
    private static let animals = AnimalLibrary.load()
    private var animals: [Animal] { Self.animals }
    private var questions: [(Animal, QuizQuestion)] { animals.flatMap { a in a.quiz.map { (a, $0) } } }

    private func photos() throws -> [String: [String: Any]] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "photos", withExtension: "json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: [String: Any]])
    }

    func testRightAnswerIsNotGivenAwayByLength() {
        let qs = questions.map(\.1)
        let longest = qs.filter { q in q.choices[0].count > q.choices.dropFirst().map(\.count).max()! }.count
        let shortest = qs.filter { q in q.choices[0].count < q.choices.dropFirst().map(\.count).min()! }.count
        XCTAssertLessThanOrEqual(Double(longest) / Double(qs.count), 0.35, "the longest choice is usually right")
        XCTAssertLessThanOrEqual(Double(shortest) / Double(qs.count), 0.35, "the shortest choice is usually right")
    }

    func testNoAllOrNoneOfTheAbove() {
        for (a, q) in questions {
            for c in q.choices { XCTAssertFalse(c.lowercased().contains("of the above"), "\(a.id): \(c)") }
        }
    }

    func testPromptsDontContainTheirAnswer() {
        for (a, q) in questions where q.choices[0].count > 6 {
            XCTAssertFalse(q.prompt.lowercased().contains(q.choices[0].lowercased()), "\(a.id): \(q.prompt)")
        }
    }

    func testTaglinesAreShortAndUnpunctuated() {
        for a in animals {
            XCTAssertLessThanOrEqual(a.tagline.count, 60, a.id)
            XCTAssertFalse(a.tagline.hasSuffix("."), a.id)
        }
    }

    func testScientificNamesAreBinomial() {
        for a in animals {
            let parts = a.scientificName.split(separator: " ")
            XCTAssertGreaterThanOrEqual(parts.count, 2, a.id)
            XCTAssertTrue(parts[0].first!.isUppercase, a.id)
            XCTAssertTrue(parts[1].first!.isLowercase, a.id)
        }
    }

    func testIDsAreKebabCase() {
        for a in animals {
            XCTAssertNotNil(a.id.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression), a.id)
        }
    }

    func testNamesHaveNoStrayWhitespace() {
        for a in animals {
            XCTAssertEqual(a.name, a.name.trimmingCharacters(in: .whitespacesAndNewlines), a.id)
            XCTAssertFalse(a.name.isEmpty, a.id)
        }
    }

    func testNoMarkdownOrPlaceholders() throws {
        let text = String(decoding: try JSONEncoder().encode(animals), as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("**"), "markdown left in the text")
        XCTAssertFalse(text.contains("[citation"), "a Wikipedia citation tag was copied")
        // Whole words only: "mastodons" contains "todo".
        for bad in ["todo", "lorem", "tbd", "xxx"] {
            XCTAssertNil(text.range(of: "\\b\(bad)\\b", options: .regularExpression), "found \(bad)")
        }
    }

    func testCurlyQuotesAreBalanced() {
        for a in animals {
            let all = [a.lede, a.home, a.life, a.remarkable, a.outlook, a.didYouKnow,
                       a.anatomy ?? "", a.family ?? "", a.people ?? "", a.relatives ?? ""].joined()
            XCTAssertEqual(all.filter { $0 == "\u{201C}" }.count, all.filter { $0 == "\u{201D}" }.count, a.id)
        }
    }

    func testLedeIsShort() {
        for a in animals { XCTAssertLessThanOrEqual(a.lede.split(separator: " ").count, 80, a.id) }
    }

    func testDidYouKnowIsShort() {
        for a in animals { XCTAssertLessThanOrEqual(a.didYouKnow.split(separator: " ").count, 70, a.id) }
    }

    func testFactLabelsAreUniquePerAnimal() {
        for a in animals { XCTAssertEqual(Set(a.facts.map(\.label)).count, a.facts.count, a.id) }
    }

    func testCharitiesAreRealOrganisations() {
        for a in animals {
            XCTAssertEqual(Set(a.charities.map(\.name)).count, a.charities.count, a.id)
            for c in a.charities {
                XCTAssertFalse(c.host.contains("wikipedia"), a.id)
                XCTAssertFalse(c.host.contains("example"), a.id)
            }
        }
    }

    func testNoAnimalSitsAtNullIsland() {
        for a in animals {
            XCTAssertFalse(abs(a.coordinate.latitude) < 0.01 && abs(a.coordinate.longitude) < 0.01, a.id)
        }
    }

    func testPhotosHaveNoStrayEntries() throws {
        XCTAssertEqual(Set(try photos().keys), Set(animals.map(\.wikipediaTitle)))
    }

    func testPhotoWidthsArePositive() throws {
        for (title, entry) in try photos() { XCTAssertGreaterThan(entry["width"] as? Int ?? 0, 0, title) }
    }

    func testPhotoPagesAreOnCommons() throws {
        for (title, entry) in try photos() {
            let credit = entry["credit"] as? [String: Any]
            XCTAssertTrue((credit?["pageURL"] as? String ?? "").hasPrefix("https://commons.wikimedia.org/"), title)
        }
    }

    func testGroupAndRegionSymbolsExist() {
        for g in AnimalGroup.allCases { XCTAssertNotNil(UIImage(systemName: g.symbol), g.symbol) }
        for r in Region.allCases { XCTAssertNotNil(UIImage(systemName: r.symbol), r.symbol) }
    }

    func testFactSymbolsExist() {
        for a in animals {
            for f in a.facts { XCTAssertNotNil(UIImage(systemName: f.symbol), "\(a.id): \(f.symbol)") }
        }
    }

    func testThreatenedAnimalsAreIncluded() {
        XCTAssertGreaterThanOrEqual(animals.filter { $0.status == .CR }.count, 3)
        XCTAssertGreaterThanOrEqual(animals.filter(\.status.isThreatened).count, 20)
    }

    func testWikipediaTitlesUseSpaces() {
        for a in animals { XCTAssertFalse(a.wikipediaTitle.contains("_"), a.id) }
    }

    func testNotificationTextFitsOnALockScreen() {
        for a in animals {
            XCTAssertLessThanOrEqual("Meet the \(a.name)".count, 45, a.id)
            XCTAssertLessThanOrEqual("\(a.tagline). \(a.readingMinutes)-minute read.".count, 110, a.id)
        }
    }
}
