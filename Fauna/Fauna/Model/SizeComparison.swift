import Foundation

/// Turns an animal's length or weight fact into a comparison with something familiar:
/// "about 1.3 times as long as a car", "as heavy as about 3 adult people".
struct SizeComparison: Equatable, Identifiable {
    enum Kind: Equatable { case length, weight }

    /// A familiar object of known size, drawn with an SF Symbol.
    struct Reference: Equatable {
        let name: String        // "a car"
        let plural: String      // "cars"
        let symbol: String
        /// Metres (lengths) or kilograms (weights).
        let size: Double
        /// True when the size is a height (a person standing), so it's drawn upright.
        var upright = false
        /// Width over height of the drawn symbol.
        var aspect: Double = 1
        /// A coin's size is its diameter.
        var measuresAcross = false
        /// What the size measures: "long", "tall", "across".
        var measure: String { upright ? "tall" : measuresAcross ? "across" : "long" }
    }

    let kind: Kind
    /// How the length is measured, for the wording: "as long as", "as tall as", "wingspan".
    enum Dimension: Equatable { case long, tall, wingspan }
    var dimension: Dimension = .long
    /// The animal's size: metres or kilograms (the upper end of a range).
    let value: Double
    let reference: Reference

    /// Things whose length (end to end) is familiar. All lie along the same axis as the animal.
    static let lengthReferences: [Reference] = [
        Reference(name: "a credit card", plural: "credit cards", symbol: "creditcard.fill", size: 0.086, aspect: 1.5),
        Reference(name: "a phone", plural: "phones", symbol: "iphone.landscape", size: 0.15, aspect: 2),
        Reference(name: "a house cat", plural: "house cats", symbol: "cat.fill", size: 0.46, aspect: 1.1),
        Reference(name: "a bicycle", plural: "bicycles", symbol: "bicycle", size: 1.75, aspect: 1.7),
        Reference(name: "a car", plural: "cars", symbol: "car.side.fill", size: 4.5, aspect: 2.2),
        Reference(name: "a truck", plural: "trucks", symbol: "truck.box.fill", size: 12, aspect: 1.9),
        Reference(name: "an airliner", plural: "airliners", symbol: "airplane", size: 38, aspect: 1.1),
    ]

    /// Things whose height is familiar, standing up, for heights and shoulder heights.
    static let heightReferences: [Reference] = [
        Reference(name: "a phone", plural: "phones", symbol: "iphone", size: 0.15, upright: true, aspect: 0.5),
        Reference(name: "a house cat", plural: "house cats", symbol: "cat.fill", size: 0.25, upright: true, aspect: 1.1),
        Reference(name: "a big dog", plural: "big dogs", symbol: "dog.fill", size: 0.6, upright: true, aspect: 1.1),
        Reference(name: "an adult person", plural: "adult people", symbol: "figure.stand", size: 1.7, upright: true, aspect: 0.45),
        Reference(name: "a truck", plural: "trucks", symbol: "truck.box.fill", size: 3.5, upright: true, aspect: 1.9),
        Reference(name: "a two-storey house", plural: "two-storey houses", symbol: "house.fill", size: 8, upright: true, aspect: 1.1),
    ]

    static let weightReferences: [Reference] = [
        Reference(name: "a phone", plural: "phones", symbol: "iphone", size: 0.2),
        Reference(name: "a bag of sugar", plural: "bags of sugar", symbol: "bag.fill", size: 1),
        Reference(name: "a house cat", plural: "house cats", symbol: "cat.fill", size: 4.5),
        Reference(name: "a big dog", plural: "big dogs", symbol: "dog.fill", size: 30),
        Reference(name: "an adult person", plural: "adult people", symbol: "figure.stand", size: 70, upright: true),
        Reference(name: "a car", plural: "cars", symbol: "car.side.fill", size: 1500),
        Reference(name: "a bus", plural: "buses", symbol: "bus.fill", size: 12000),
    ]

    /// A coin people actually carry where the phone is set up: its diameter and weight.
    struct Coin { let name: String; let plural: String; let symbol: String; let diameter: Double; let mass: Double }

    static func coin(region: String?) -> Coin {
        let euro: Set<String> = ["AT", "BE", "CY", "DE", "EE", "ES", "FI", "FR", "GR", "HR", "IE", "IT", "LT", "LU",
                                 "LV", "MT", "NL", "PT", "SI", "SK"]
        switch region ?? "" {
        case "CA": return Coin(name: "a Canadian quarter", plural: "Canadian quarters", symbol: "centsign.circle.fill",
                               diameter: 0.02388, mass: 0.0044)
        case "GB": return Coin(name: "a £1 coin", plural: "£1 coins", symbol: "sterlingsign.circle.fill",
                               diameter: 0.02343, mass: 0.00875)
        case "AU": return Coin(name: "an Australian $1 coin", plural: "Australian $1 coins", symbol: "dollarsign.circle.fill",
                               diameter: 0.025, mass: 0.009)
        case "NZ": return Coin(name: "a NZ $1 coin", plural: "NZ $1 coins", symbol: "dollarsign.circle.fill",
                               diameter: 0.023, mass: 0.008)
        case let r where euro.contains(r):
            return Coin(name: "a €1 coin", plural: "€1 coins", symbol: "eurosign.circle.fill", diameter: 0.02325, mass: 0.0075)
        default: return Coin(name: "a US quarter", plural: "US quarters", symbol: "centsign.circle.fill",
                             diameter: 0.02426, mass: 0.00567)
        }
    }

    static func references(_ kind: Kind, region: String?) -> [Reference] {
        let c = coin(region: region)
        if kind == .length {
            return [Reference(name: c.name, plural: c.plural, symbol: c.symbol, size: c.diameter, measuresAcross: true)]
                + lengthReferences
        }
        return [Reference(name: c.name, plural: c.plural, symbol: c.symbol, size: c.mass)] + weightReferences
    }

    private static let lengthLabels: Set<String> = ["length", "body length", "wingspan", "height", "shoulder height",
                                                     "shell length", "total length", "size", "head-body length"]

    /// A comparison for a fact, or nil when it isn't a length or weight with a readable number.
    /// `fact` must be the original, metric fact.
    static func make(for fact: Fact, region: String? = Locale.current.region?.identifier) -> SizeComparison? {
        let label = fact.label.lowercased()
        let kind: Kind
        if label == "weight" { kind = .weight } else if lengthLabels.contains(label) { kind = .length } else { return nil }
        guard let value = parse(fact.value, kind: kind), value > 0 else { return nil }
        let dimension: Dimension = label.contains("height") ? .tall : label == "wingspan" ? .wingspan : .long
        // Like with like: a height against heights, a length against lengths.
        let refs = kind == .length && dimension == .tall ? heightReferences : references(kind, region: region)
        // The familiar object closest in size, so the picture stays readable.
        let reference = refs.min { abs(log($0.size / value)) < abs(log($1.size / value)) }!
        return SizeComparison(kind: kind, dimension: dimension, value: value, reference: reference)
    }

    /// The biggest number in the first measurement, in metres or kilograms.
    static func parse(_ text: String, kind: Kind) -> Double? {
        let number = #"\d[\d,]*(?:\.\d+)?"#
        let pattern = "(\(number))(?:\\s?(?:–|-|to)\\s?(\(number)))?\\s?(mm|cm|km|m|kg|g|tonnes|tonne|t)(?![A-Za-z])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let unit = ns.substring(with: match.range(at: 3))
            let factor: Double
            switch (kind, unit) {
            case (.length, "mm"): factor = 0.001
            case (.length, "cm"): factor = 0.01
            case (.length, "m"): factor = 1
            case (.length, "km"): factor = 1000
            case (.weight, "g"): factor = 0.001
            case (.weight, "kg"): factor = 1
            case (.weight, "tonne"), (.weight, "tonnes"), (.weight, "t"): factor = 1000
            default: continue
            }
            func value(_ i: Int) -> Double? {
                let r = match.range(at: i)
                guard r.location != NSNotFound else { return nil }
                return Double(ns.substring(with: r).replacingOccurrences(of: ",", with: ""))
            }
            guard let a = value(1) else { continue }
            return max(a, value(2) ?? a) * factor
        }
        return nil
    }

    var id: String { "\(kind)-\(value)" }

    /// How many of the reference the animal measures.
    var ratio: Double { value / reference.size }

    /// "The Saltwater Crocodile is about 1.3 times as long as a car."
    func sentence(animal: String) -> String {
        let r = ratio
        let close = r >= 0.85 && r <= 1.2
        switch (kind, dimension) {
        case (.length, .wingspan):
            if close { return "The \(animal)'s wingspan is about the length of \(reference.name)." }
            if r > 1.2 { return "The \(animal)'s wingspan is about \(Self.times(r)) times the length of \(reference.name)." }
            return "The \(animal)'s wingspan is about \(Self.fraction(r)) the length of \(reference.name)."
        case (.length, _):
            let adjective = dimension == .tall ? "tall" : "long"
            if close { return "The \(animal) is about as \(adjective) as \(reference.name)." }
            if r > 1.2 { return "The \(animal) is about \(Self.times(r)) times as \(adjective) as \(reference.name)." }
            return "The \(animal) is about \(Self.fraction(r)) as \(adjective) as \(reference.name)."
        case (.weight, _):
            if close { return "The \(animal) is about as heavy as \(reference.name)." }
            if r > 1.2 {
                if r < 1.5 { return "The \(animal) is a little heavier than \(reference.name)." }
                return "The \(animal) weighs about as much as \(Self.count(r)) \(reference.plural)."
            }
            return "The \(animal) is about \(Self.fraction(r)) as heavy as \(reference.name)."
        }
    }

    static func times(_ r: Double) -> String {
        if r >= 10 { return Int(r.rounded()).formatted() }
        return trimmed(String(format: "%.1f", r))
    }

    private static func trimmed(_ s: String) -> String { s.hasSuffix(".0") ? String(s.dropLast(2)) : s }

    static func count(_ r: Double) -> String {
        let n = r < 20 ? Int(r.rounded()) : Int((r / 5).rounded() * 5)
        return n.formatted()
    }

    static func fraction(_ r: Double) -> String {
        switch r {
        case 0.6...: "two-thirds"
        case 0.4..<0.6: "half"
        case 0.29..<0.4: "a third"
        case 0.22..<0.29: "a quarter"
        default: "1/\(Int((1 / r).rounded()))"
        }
    }

    /// The animal's size as metric text ("6 m", "35 g"), for the reader's units to convert.
    var valueText: String { Self.text(value, kind: kind) }
    var referenceText: String { Self.text(reference.size, kind: kind) }

    static func text(_ v: Double, kind: Kind) -> String {
        func n(_ x: Double) -> String {
            x >= 100 ? Int(x.rounded()).formatted() : trimmed(String(format: x < 10 ? "%.1f" : "%.0f", x))
        }
        switch kind {
        case .length:
            if v < 0.01 { return "\(n(v * 1000)) mm" }
            if v < 1 { return "\(n(v * 100)) cm" }
            return "\(n(v)) m"
        case .weight:
            if v < 1 { return "\(n(v * 1000)) g" }
            if v < 1000 { return "\(n(v)) kg" }
            let t = n(v / 1000)
            return t == "1" ? "1 tonne" : "\(t) tonnes"
        }
    }
}
