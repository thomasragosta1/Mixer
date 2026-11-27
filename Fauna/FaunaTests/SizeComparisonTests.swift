import XCTest
@testable import Fauna

final class SizeComparisonTests: XCTestCase {
    private func fact(_ label: String, _ value: String) -> Fact { Fact(label: label, value: value) }

    func testParsesTheTopOfARange() {
        XCTAssertEqual(SizeComparison.parse("50–64 cm + tail", kind: .length)!, 0.64, accuracy: 0.0001)
        XCTAssertEqual(SizeComparison.parse("Up to 1,000–1,500 kg", kind: .weight)!, 1500, accuracy: 0.01)
        XCTAssertEqual(SizeComparison.parse("30–35 g, queens up to 80 g", kind: .weight)!, 0.035, accuracy: 0.0001)
        XCTAssertEqual(SizeComparison.parse("Males up to about 6 m", kind: .length)!, 6, accuracy: 0.0001)
        XCTAssertEqual(SizeComparison.parse("8 mm", kind: .length)!, 0.008, accuracy: 0.00001)
        XCTAssertEqual(SizeComparison.parse("Up to 2 tonnes", kind: .weight)!, 2000, accuracy: 0.01)
    }

    func testOnlyLengthsAndWeightsCompare() {
        XCTAssertNil(SizeComparison.make(for: fact("Lifespan", "8–10 years")))
        XCTAssertNil(SizeComparison.make(for: fact("Diet", "Mostly bamboo")))
        XCTAssertNil(SizeComparison.make(for: fact("Weight", "Unknown")))
        XCTAssertNil(SizeComparison.make(for: fact("Length", "40 kg")), "a weight in a length fact is ignored")
        XCTAssertEqual(SizeComparison.make(for: fact("Wingspan", "3 m"))?.kind, .length)
        XCTAssertEqual(SizeComparison.make(for: fact("Weight", "3 kg"))?.kind, .weight)
    }

    func testPicksTheClosestFamiliarThing() {
        XCTAssertEqual(SizeComparison.make(for: fact("Length", "Up to about 6 m"))?.reference.name, "a car")
        XCTAssertEqual(SizeComparison.make(for: fact("Length", "1.8 m"))?.reference.name, "a bicycle")
        XCTAssertEqual(SizeComparison.make(for: fact("Height", "1.8 m"))?.reference.name, "an adult person")
        XCTAssertEqual(SizeComparison.make(for: fact("Length", "8 mm"), region: "US")?.reference.name, "a US quarter")
        XCTAssertEqual(SizeComparison.make(for: fact("Weight", "150 tonnes"))?.reference.name, "a bus")
        XCTAssertEqual(SizeComparison.make(for: fact("Weight", "3–6 kg"))?.reference.name, "a house cat")
    }

    func testSentencesReadNaturally() {
        let croc = SizeComparison.make(for: fact("Length", "Males up to about 6 m"))!
        XCTAssertEqual(croc.sentence(animal: "Saltwater Crocodile"),
                       "The Saltwater Crocodile is about 1.3 times as long as a car.")
        let heavy = SizeComparison.make(for: fact("Weight", "Up to 1,000–1,500 kg"))!
        XCTAssertEqual(heavy.sentence(animal: "Saltwater Crocodile"), "The Saltwater Crocodile is about as heavy as a car.")
        let whale = SizeComparison.make(for: fact("Weight", "144 tonnes"))!
        XCTAssertEqual(whale.sentence(animal: "Blue Whale"), "The Blue Whale weighs about as much as 12 buses.")
        let small = SizeComparison.make(for: fact("Length", "8 cm"))!
        XCTAssertEqual(small.sentence(animal: "Naked Mole-rat"), "The Naked Mole-rat is about as long as a credit card.")
        let panda = SizeComparison.make(for: fact("Weight", "3–6 kg"))!
        XCTAssertEqual(panda.sentence(animal: "Red Panda"), "The Red Panda is a little heavier than a house cat.")
    }

    func testHeightsAndWingspansAreWordedForWhatTheyMeasure() {
        let rhino = SizeComparison.make(for: fact("Shoulder height", "1.32–1.8 m"))!
        XCTAssertEqual(rhino.sentence(animal: "Black Rhinoceros"), "The Black Rhinoceros is about as tall as an adult person.")
        let albatross = SizeComparison.make(for: fact("Wingspan", "Up to 3.5 m"))!
        XCTAssertEqual(albatross.sentence(animal: "Wandering Albatross"),
                       "The Wandering Albatross's wingspan is about two-thirds the length of a car.")
    }

    func testTheCoinIsOneYouKnow() {
        let tiny = fact("Length", "35 mm")
        XCTAssertEqual(SizeComparison.make(for: tiny, region: "US")?.reference.name, "a US quarter")
        XCTAssertEqual(SizeComparison.make(for: tiny, region: "CA")?.reference.name, "a Canadian quarter")
        XCTAssertEqual(SizeComparison.make(for: tiny, region: "GB")?.reference.name, "a £1 coin")
        XCTAssertEqual(SizeComparison.make(for: tiny, region: "FR")?.reference.name, "a €1 coin")
        XCTAssertEqual(SizeComparison.make(for: tiny, region: "AU")?.reference.name, "an Australian $1 coin")
        XCTAssertEqual(SizeComparison.make(for: tiny, region: nil)?.reference.name, "a US quarter")
        XCTAssertEqual(SizeComparison.make(for: tiny, region: "US")?.reference.measure, "across")
        XCTAssertEqual(SizeComparison.make(for: fact("Weight", "6 g"), region: "CA")?.reference.plural, "Canadian quarters")
        for region in ["US", "CA", "GB", "DE", "AU", "NZ", "JP"] {
            let c = SizeComparison.make(for: tiny, region: region)!
            XCTAssertFalse(c.sentence(animal: "Spring Peeper").contains("a coin"), region)
        }
    }

    func testHeightsCompareWithHeightsAndLengthsWithLengths() {
        for f in ["Length", "Body length", "Wingspan", "Shell length"] {
            for v in ["2 cm", "30 cm", "1.2 m", "6 m", "20 m"] {
                let c = SizeComparison.make(for: fact(f, v), region: "US")!
                XCTAssertFalse(c.reference.upright, "\(f) \(v) compared with a height (\(c.reference.name))")
                XCTAssertNotEqual(c.reference.measure, "tall")
            }
        }
        for f in ["Height", "Shoulder height"] {
            for v in ["10 cm", "30 cm", "1 m", "1.8 m", "5.5 m"] {
                let c = SizeComparison.make(for: fact(f, v), region: "US")!
                XCTAssertTrue(c.reference.upright, "\(f) \(v) compared with a length (\(c.reference.name))")
                XCTAssertEqual(c.reference.measure, "tall")
                XCTAssertTrue(c.sentence(animal: "Giraffe").contains("tall"))
            }
        }
        XCTAssertEqual(SizeComparison.make(for: fact("Height", "Up to 5.5 m"))?.reference.name, "a two-storey house")
        XCTAssertEqual(SizeComparison.make(for: fact("Length", "29–33 cm"), region: "US")?.sentence(animal: "Atlantic Puffin"),
                       "The Atlantic Puffin is about two-thirds as long as a house cat.")
    }

    func testMetricTextForTheReadersUnits() {
        XCTAssertEqual(SizeComparison.text(6, kind: .length), "6 m")
        XCTAssertEqual(SizeComparison.text(0.64, kind: .length), "64 cm")
        XCTAssertEqual(SizeComparison.text(0.008, kind: .length), "8 mm")
        XCTAssertEqual(SizeComparison.text(1.7, kind: .length), "1.7 m")
        XCTAssertEqual(SizeComparison.text(1000, kind: .weight), "1 tonne")
        XCTAssertEqual(SizeComparison.text(150_000, kind: .weight), "150 tonnes")
        XCTAssertEqual(SizeComparison.text(0.035, kind: .weight), "35 g")
    }

    func testMostAnimalsHaveAComparison() {
        let animals = AnimalLibrary.load()
        let comparable = animals.filter { $0.facts.contains { SizeComparison.make(for: $0) != nil } }
        XCTAssertGreaterThan(Double(comparable.count) / Double(animals.count), 0.85)
        for a in animals {
            for f in a.facts {
                if let c = SizeComparison.make(for: f) {
                    XCTAssertFalse(c.sentence(animal: a.name).contains("nan"), a.id)
                    XCTAssertTrue(c.value.isFinite && c.value > 0, a.id)
                }
            }
        }
    }
}

final class SilhouetteTests: XCTestCase {
    func testMostAnimalsHaveACreditedSilhouette() {
        let animals = AnimalLibrary.load()
        let with = animals.filter { Silhouettes.image(for: $0.id) != nil }
        XCTAssertGreaterThan(Double(with.count) / Double(animals.count), 0.9)
        for a in with {
            let credit = Silhouettes.credits[a.id]
            XCTAssertNotNil(credit, "\(a.id) has a silhouette but no credit")
            XCTAssertNotNil(Silhouettes.creditLine(for: a.id), a.id)
            XCTAssertFalse(credit?.licenseURL.lowercased().contains("/nc") ?? true, "\(a.id): non-commercial licence")
        }
    }
}
