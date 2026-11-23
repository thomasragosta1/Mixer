import XCTest
@testable import Fauna

/// One test per unit spelling and per rounding band, so a regression names exactly what broke.
final class UnitsByUnitTests: XCTestCase {
    private func imperial(_ s: String) -> String { UnitText.localize(s, imperial: true) }

    func testKmPerHour() { XCTAssertEqual(imperial("12 km/h"), "7.5 mph") }
    func testMetresPerSecondSmall() { XCTAssertEqual(imperial("4 m/s"), "8.9 mph") }
    func testMillimetresSymbol() { XCTAssertEqual(imperial("8 mm"), "0.31 in") }
    func testCentimetresSymbol() { XCTAssertEqual(imperial("30 cm"), "12 in") }
    func testCentimetresToFeet() { XCTAssertEqual(imperial("200 cm"), "6.6 ft") }
    func testCentimetresPromoteAtTheShownValue() { XCTAssertEqual(imperial("91 cm"), "3 ft") }
    func testMetresSmall() { XCTAssertEqual(imperial("3 m"), "9.8 ft") }
    func testKilometresSymbol() { XCTAssertEqual(imperial("250 km"), "155 mi") }
    func testGramsSymbol() { XCTAssertEqual(imperial("40 g"), "1.4 oz") }
    func testGramsPromoteAtTheShownValue() { XCTAssertEqual(imperial("900 g"), "2 lb") }
    func testKilogramsSymbol() { XCTAssertEqual(imperial("70 kg"), "155 lb") }
    func testOneTonne() { XCTAssertEqual(imperial("1 tonne"), "1.1 tons") }
    func testTonnesPlural() { XCTAssertEqual(imperial("5 tonnes"), "5.5 tons") }
    func testMillimetresWord() { XCTAssertEqual(imperial("6 millimetres"), "0.24 in") }
    func testCentimetresWordSmall() { XCTAssertEqual(imperial("2 centimetres"), "0.79 inches") }
    func testCentimetresWordMedium() { XCTAssertEqual(imperial("40 centimetres"), "16 inches") }
    func testMetreSingular() { XCTAssertEqual(imperial("1 metre"), "3.3 feet") }
    func testAmericanMeters() { XCTAssertEqual(imperial("10 meters"), "33 feet") }
    func testKilometreSingular() { XCTAssertEqual(imperial("1 kilometre"), "0.62 miles") }
    func testAmericanKilometers() { XCTAssertEqual(imperial("8 kilometers"), "5 miles") }
    func testGramsWord() { XCTAssertEqual(imperial("15 grams"), "0.53 ounces") }
    func testKilogramsWord() { XCTAssertEqual(imperial("50 kilograms"), "110 pounds") }
    func testSquareKilometreSymbol() { XCTAssertEqual(imperial("45 km²"), "17 sq mi") }
    func testAmericanSquareKilometers() { XCTAssertEqual(imperial("3 square kilometers"), "1.2 square miles") }
    func testNoSpaceBeforeUnit() { XCTAssertEqual(imperial("30m"), "98 ft") }
    func testHyphenRange() { XCTAssertEqual(imperial("2-3 m"), "6.6-9.8 ft") }
    func testAndRange() { XCTAssertEqual(imperial("10 and 20 kg"), "22 and 44 lb") }
    func testTenThousandsRoundToHundreds() { XCTAssertEqual(imperial("12,000 km"), "7,450 mi") }
    func testBelowOneKeepsTwoSignificantFigures() { XCTAssertEqual(imperial("0.3 m"), "0.98 ft") }
    func testTinyWeightsNeverShowAsZero() { XCTAssertEqual(imperial("0.04 g"), "0.0014 oz") }
    func testLargeWeights() { XCTAssertEqual(imperial("35,000 kg"), "77,200 lb") }
    func testThousandsRoundToFifty() { XCTAssertEqual(imperial("1,200 kg"), "2,650 lb") }
}
