import SwiftUI

extension AnimalGroup {
    /// iOS system colors, so the palette adapts to dark mode and increased contrast.
    var color: Color {
        switch self {
        case .mammal: .orange
        case .bird: .blue
        case .reptile: .green
        case .amphibian: .teal
        case .fish: .indigo
        case .insect: .yellow
        case .marineInvertebrate: .pink
        }
    }

    /// Two tones used for placeholder art while a photo loads.
    var gradient: [Color] {
        [color.blended(with: .black, by: 0.25), color.blended(with: .black, by: 0.5)]
    }
}

extension ConservationStatus {
    var color: Color {
        switch self {
        case .LC: .green
        case .NT: .mint
        case .VU: .yellow
        case .EN: .orange
        case .CR: .red
        case .EW: .purple
        case .EX: Color(.systemGray)
        case .DD, .NE: Color(.systemGray2)
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

    /// Near-black surfaces for the onboarding and unlock card.
    static let faunaInk = Color(white: 0.06)
    static let faunaForest = Color(white: 0.12)
    /// The app's green: close to iOS system green, a touch calmer.
    static let faunaMoss = Color(red: 0.20, green: 0.68, blue: 0.37)
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
                Capsule().fill(tint)
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
