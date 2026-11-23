import XCTest
@testable import Fauna

/// Metric-to-imperial rewriting of article text. Expected values follow the app's rounding:
/// two significant figures under 10, whole numbers under 100, then steps of 5, 50 and 100.
final class UnitsTests: XCTestCase {
    private func imperial(_ s: String) -> String { UnitText.localize(s, imperial: true) }

    func testMetricLeavesTextAlone() {
        XCTAssertEqual(UnitText.localize("Up to 30 m long and 3–6 kg", imperial: false), "Up to 30 m long and 3–6 kg")
    }

    func testKilogramRange() { XCTAssertEqual(imperial("3–6 kg"), "6.6–13 lb") }
    func testSpeed() { XCTAssertEqual(imperial("speeds of over 100 km/h."), "speeds of over 62 mph.") }
    func testMetresSymbol() { XCTAssertEqual(imperial("Up to ~30 m"), "Up to ~98 ft") }
    func testKilometresWordWithThousands() { XCTAssertEqual(imperial("up to 4,500 kilometres"), "up to 2,800 miles") }
    func testCentimetresStayInches() { XCTAssertEqual(imperial("50 cm"), "20 in") }
    func testCentimetresPromoteToFeet() { XCTAssertEqual(imperial("120 cm"), "3.9 ft") }
    func testMillimetres() { XCTAssertEqual(imperial("17–24 mm"), "0.67–0.94 in") }
    func testGramsStayOunces() { XCTAssertEqual(imperial("About 200 g"), "About 7.1 oz") }
    func testGramsPromoteToPounds() { XCTAssertEqual(imperial("2,000 g"), "4.4 lb") }
    func testTonnes() { XCTAssertEqual(imperial("Up to 6–7 tonnes"), "Up to 6.6–7.7 tons") }
    func testMetresPerSecond() { XCTAssertEqual(imperial("About 23 m/s"), "About 51 mph") }
    func testSpelledOutUnits() {
        XCTAssertEqual(imperial("around 100 kilograms"), "around 220 pounds")
        XCTAssertEqual(imperial("dive to around 60 metres"), "dive to around 195 feet")
        XCTAssertEqual(imperial("about 7 centimetres"), "about 2.8 inches")
    }

    func testSquareKilometresAreAreasNotLengths() {
        XCTAssertEqual(imperial("can exceed 20 square kilometres"), "can exceed 7.7 square miles")
        XCTAssertEqual(imperial("up to 1,000 km²"), "up to 385 sq mi")
    }

    func testRangeWithTo() { XCTAssertEqual(imperial("2 to 4 m"), "6.6 to 13 ft") }
    func testDecimals() { XCTAssertEqual(imperial("About 1.5 m"), "About 4.9 ft") }

    func testUnitLettersInsideWordsAreIgnored() {
        XCTAssertEqual(imperial("5 mice and 3 geese"), "5 mice and 3 geese")
        XCTAssertEqual(imperial("in 1980 many died"), "in 1980 many died")
    }

    func testNumberWordsAreNotConverted() {
        XCTAssertEqual(imperial("seven metres"), "seven metres")
    }

    func testSeveralMeasurementsInOneSentence() {
        XCTAssertEqual(imperial("3 metres and 11 kg, flying 12 km"), "9.8 feet and 24 lb, flying 7.5 mi")
    }

    func testEmptyAndUnitlessText() {
        XCTAssertEqual(imperial(""), "")
        XCTAssertEqual(imperial("No numbers here."), "No numbers here.")
    }

    func testPreferenceFlags() {
        XCTAssertFalse(UnitPreference.metric.usesImperial)
        XCTAssertTrue(UnitPreference.imperial.usesImperial)
        XCTAssertEqual(UnitPreference.automatic.usesImperial, Locale.current.measurementSystem == .us)
        XCTAssertEqual(UnitPreference.allCases.map(\.title), ["Automatic", "Metric", "Imperial"])
    }

    /// Every sentence in the library converts without leaving a metric unit behind next to a number.
    func testWholeLibraryConvertsCleanly() throws {
        let leftover = try NSRegularExpression(pattern: #"\d\s?(km/h|km|kg|cm|mm|kilometres?|metres?|grams?|tonnes?)(?![A-Za-z])"#)
        for a in AnimalLibrary.load() {
            var texts = [a.lede, a.home, a.life, a.remarkable, a.outlook, a.didYouKnow, a.range,
                         a.anatomy ?? "", a.family ?? "", a.people ?? "", a.relatives ?? ""]
            texts += a.facts.map(\.value)
            texts += a.quiz.flatMap { [$0.prompt, $0.explanation] + $0.choices }
            for t in texts {
                let out = imperial(t)
                let ns = out as NSString
                XCTAssertNil(leftover.firstMatch(in: out, range: NSRange(location: 0, length: ns.length)),
                             "\(a.id): \(out)")
            }
        }
    }

    /// Hammer the converter with random measurement strings: it must never crash or emit NaN.
    func testRandomMeasurementsStress() {
        let units = ["mm", "cm", "m", "km", "g", "kg", "tonnes", "km/h", "m/s", "metres", "kilometres", "grams",
                     "kilograms", "centimetres", "millimetres", "square kilometres", "km²"]
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2_000 {
            let a = Double(Int.random(in: 0...50_000, using: &rng)) / 10
            let b = a + Double(Int.random(in: 1...5_000, using: &rng)) / 10
            let unit = units.randomElement(using: &rng)!
            let text = Bool.random() ? "about \(a) \(unit) long" : "\(a)–\(b) \(unit)"
            let out = imperial(text)
            XCTAssertFalse(out.contains("nan") || out.contains("inf"), out)
            XCTAssertNotEqual(out, text, text)
        }
    }
}
