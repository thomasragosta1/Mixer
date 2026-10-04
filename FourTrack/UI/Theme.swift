import SwiftUI

/// Shared look, following the current iOS design: larger continuous corner
/// radii, content on plain cards, and floating controls on Liquid Glass
/// (iOS 26+; earlier versions get a translucent material instead).
enum Theme {
    /// Content cards (track lanes, mixer cards).
    static let cardRadius: CGFloat = 22
    /// Things inside a card (waveform well, pads).
    static let innerRadius: CGFloat = 14
    /// Floating panels (transport, banners, pop-ups).
    static let panelRadius: CGFloat = 30
}

extension View {
    /// Floating control surface: Liquid Glass on iOS 26, material before.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = Theme.panelRadius) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }

    /// Prominent capsule button (tinted glass on iOS 26).
    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }

    /// Secondary capsule button (clear glass on iOS 26).
    @ViewBuilder
    func glassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}
