import SwiftUI

extension AnimalGroup {
    /// System colors, so the palette adapts to light, dark and increased contrast like Apple's apps.
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
        [color.blended(with: .black, by: 0.15), color.blended(with: .black, by: 0.55)]
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

    static let faunaInk = Color(red: 0.05, green: 0.13, blue: 0.11)
    static let faunaForest = Color(red: 0.07, green: 0.26, blue: 0.20)
    static let faunaMoss = Color.green
    static let faunaGold = Color.yellow
}

/// San Francisco throughout, sized from Dynamic Type styles.
enum FaunaFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
    static let eyebrow = Font.footnote.weight(.semibold)
    static let body = Font.body
    static let lede = Font.title3
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

/// The large, filled button Apple uses at the bottom of welcome screens and sheets.
struct ProminentPillStyle: ButtonStyle {
    var tint: Color = .accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}
