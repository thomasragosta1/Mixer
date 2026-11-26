import Foundation

/// How measurements are shown. Automatic follows Settings › General › Language & Region.
enum UnitPreference: String, Codable, CaseIterable, Identifiable {
    case automatic, metric, imperial
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }

    var usesImperial: Bool {
        switch self {
        case .metric: false
        case .imperial: true
        case .automatic: Locale.current.measurementSystem == .us
        }
    }
}

/// The kinds of measurement that can be switched separately. Speeds and areas count as distance.
enum MeasureKind: String, Codable, CaseIterable, Identifiable {
    case length, weight, distance
    var id: String { rawValue }

    var title: String {
        switch self {
        case .length: "Length"
        case .weight: "Weight"
        case .distance: "Distance"
        }
    }

    /// Short segment labels, e.g. "cm, m" or "in, ft".
    func label(imperial: Bool) -> String {
        switch self {
        case .length: imperial ? "in, ft" : "cm, m"
        case .weight: imperial ? "oz, lb" : "g, kg"
        case .distance: imperial ? "mi, mph" : "km, km/h"
        }
    }

    /// For the caption: "feet", "kilograms"...
    func noun(imperial: Bool) -> String {
        switch self {
        case .length: imperial ? "feet" : "metres"
        case .weight: imperial ? "pounds" : "kilograms"
        case .distance: imperial ? "miles" : "kilometres"
        }
    }
}

/// Rewrites the metric measurements in Fauna's text ("3–6 kg", "4,500 kilometres",
/// "up to 30 m", "100 km/h") into US customary units. Content is written in metric.
enum UnitText {
    private struct Rule {
        let factor: Double
        let unit: String
        let unitPlural: String
        var kind: MeasureKind = .length
        /// Above this many target units, switch to the bigger unit (inches → feet).
        var promote: (limit: Double, factor: Double, unit: String, plural: String)? = nil
    }

    private static let rules: [String: Rule] = {
        let inch = Rule(factor: 1 / 2.54, unit: "in", unitPlural: "in", promote: (36, 1 / 12, "ft", "ft"))
        let mm = Rule(factor: 1 / 25.4, unit: "in", unitPlural: "in")
        let ft = Rule(factor: 3.28084, unit: "ft", unitPlural: "ft")
        let feetWord = Rule(factor: 3.28084, unit: "foot", unitPlural: "feet")
        let mi = Rule(factor: 0.621371, unit: "mi", unitPlural: "mi", kind: .distance)
        let miWord = Rule(factor: 0.621371, unit: "mile", unitPlural: "miles", kind: .distance)
        let oz = Rule(factor: 1 / 28.3495, unit: "oz", unitPlural: "oz", kind: .weight, promote: (32, 1 / 16, "lb", "lb"))
        let ozWord = Rule(factor: 1 / 28.3495, unit: "ounce", unitPlural: "ounces", kind: .weight)
        let lb = Rule(factor: 2.20462, unit: "lb", unitPlural: "lb", kind: .weight)
        let lbWord = Rule(factor: 2.20462, unit: "pound", unitPlural: "pounds", kind: .weight)
        let tons = Rule(factor: 1.10231, unit: "ton", unitPlural: "tons", kind: .weight)
        let mph = Rule(factor: 0.621371, unit: "mph", unitPlural: "mph", kind: .distance)
        let mps = Rule(factor: 2.23694, unit: "mph", unitPlural: "mph", kind: .distance)
        // Areas: "20 square kilometres" must not be converted like a length.
        let sqmi = Rule(factor: 0.386102, unit: "sq mi", unitPlural: "sq mi", kind: .distance)
        let sqmiWord = Rule(factor: 0.386102, unit: "square mile", unitPlural: "square miles", kind: .distance)
        let inWord = Rule(factor: 1 / 2.54, unit: "inch", unitPlural: "inches",
                          promote: (36, 1 / 12, "foot", "feet"))
        return [
            "km/h": mph, "m/s": mps,
            "mm": mm, "cm": inch, "m": ft, "km": mi, "g": oz, "kg": lb,
            "tonne": tons, "tonnes": tons,
            "millimetre": mm, "millimetres": mm,
            "centimetre": inWord, "centimetres": inWord,
            "metre": feetWord, "metres": feetWord, "meter": feetWord, "meters": feetWord,
            "kilometre": miWord, "kilometres": miWord, "kilometer": miWord, "kilometers": miWord,
            "gram": ozWord, "grams": ozWord,
            "kilogram": lbWord, "kilograms": lbWord,
            "km²": sqmi,
            "square kilometre": sqmiWord, "square kilometres": sqmiWord,
            "square kilometer": sqmiWord, "square kilometers": sqmiWord,
        ]
    }()

    private static let number = #"\d[\d,]*(?:\.\d+)?"#
    private static let regex: NSRegularExpression = {
        let units = rules.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = "(\(number))(?:(\\s?(?:–|-|to|and)\\s?)(\(number)))?\\s?(\(units))(?![A-Za-z])"
        return try! NSRegularExpression(pattern: pattern)
    }()

    static func localize(_ text: String, imperial: Bool) -> String {
        localize(text, imperial: imperial ? Set(MeasureKind.allCases) : [])
    }

    /// Converts only the kinds in `imperial`; the rest stay metric.
    static func localize(_ text: String, imperial kinds: Set<MeasureKind>) -> String {
        guard !kinds.isEmpty else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let unitKey = ns.substring(with: match.range(at: 4))
            guard let rule = rules[unitKey], kinds.contains(rule.kind),
                  let a = value(ns.substring(with: match.range(at: 1))) else { continue }
            let b = match.range(at: 3).location != NSNotFound ? value(ns.substring(with: match.range(at: 3))) : nil
            let joiner = match.range(at: 2).location != NSNotFound ? ns.substring(with: match.range(at: 2)) : nil

            var factor = rule.factor
            var unit = (b ?? a) * factor == 1 ? rule.unit : rule.unitPlural
            // Promote on the value as it will be shown, so 31.7 oz (shown as 32) becomes 2 lb.
            if let p = rule.promote, rounded(max(a, b ?? a) * factor) >= p.limit {
                factor *= p.factor
                unit = p.plural
            }
            var out = format(a * factor)
            if let b, let joiner { out += joiner + format(b * factor) }
            out += " " + unit

            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += out
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func value(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ""))
    }

    /// Two significant figures for small values, whole numbers in the middle, rounded tens and
    /// hundreds for big ones, so converted numbers don't look falsely precise.
    private static func format(_ v: Double) -> String {
        // Below 1, keep two significant figures so tiny weights don't round to "0 oz".
        if v > 0, v < 1 { return v.formatted(.number.precision(.significantDigits(1...2))) }
        return rounded(v).formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func rounded(_ v: Double) -> Double {
        switch v {
        case ..<1: (v * 100).rounded() / 100
        case ..<10: (v * 10).rounded() / 10
        case ..<100: v.rounded()
        case ..<1000: (v / 5).rounded() * 5
        case ..<10000: (v / 50).rounded() * 50
        default: (v / 100).rounded() * 100
        }
    }
}
