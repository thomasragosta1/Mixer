import SwiftUI

extension AnimalGroup {
    var color: Color {
        switch self {
        case .mammal: Color(red: 0.80, green: 0.45, blue: 0.24)
        case .bird: Color(red: 0.22, green: 0.55, blue: 0.86)
        case .reptile: Color(red: 0.42, green: 0.60, blue: 0.24)
        case .amphibian: Color(red: 0.12, green: 0.64, blue: 0.54)
        case .fish: Color(red: 0.10, green: 0.42, blue: 0.78)
        case .insect: Color(red: 0.90, green: 0.60, blue: 0.10)
        case .marineInvertebrate: Color(red: 0.86, green: 0.32, blue: 0.46)
        }
    }

    /// Two tones used for placeholder art while a photo loads.
    var gradient: [Color] {
        [color.blended(with: .black, by: 0.15), color.blended(with: .black, by: 0.55)]
    }
}

extension ConservationStatus {
    var color: Color {
        switch self {
        case .LC: Color(red: 0.20, green: 0.66, blue: 0.40)
        case .NT: Color(red: 0.55, green: 0.72, blue: 0.20)
        case .VU: Color(red: 0.93, green: 0.70, blue: 0.10)
        case .EN: Color(red: 0.95, green: 0.47, blue: 0.13)
        case .CR: Color(red: 0.88, green: 0.20, blue: 0.20)
        case .EW: Color(red: 0.55, green: 0.25, blue: 0.62)
        case .EX: Color(red: 0.25, green: 0.25, blue: 0.27)
        case .DD, .NE: Color.gray
        }
    }
}

extension Color {
    /// Blend toward another color (works on iOS 17, unlike `mix(with:by:)`).
    func blended(with other: Color, by amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                     blue: b1 + (b2 - b1) * t, opacity: a1 + (a2 - a1) * t)
    }

    static let faunaInk = Color(red: 0.05, green: 0.13, blue: 0.11)
    static let faunaForest = Color(red: 0.07, green: 0.26, blue: 0.20)
    static let faunaMoss = Color(red: 0.30, green: 0.55, blue: 0.36)
    static let faunaGold = Color(red: 0.96, green: 0.78, blue: 0.42)
}

enum FaunaFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static let eyebrow = Font.system(.caption, design: .rounded).weight(.bold)
    static let body = Font.system(.body, design: .serif)
    static let lede = Font.system(.title3, design: .serif)
}

/// Uppercase, tracked label used above headings.
struct Eyebrow: View {
    let text: String
    var color: Color = .secondary
    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text.uppercased())
            .font(FaunaFont.eyebrow)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// Gentle press-down scale for tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The big, pill-shaped primary action.
struct ProminentPillStyle: ButtonStyle {
    var tint: Color = .accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                Capsule().fill(tint.gradient)
                    .shadow(color: tint.opacity(0.35), radius: configuration.isPressed ? 4 : 14, y: configuration.isPressed ? 2 : 8)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}
