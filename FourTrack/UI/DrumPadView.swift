import SwiftUI
import UIKit
import FourTrackCore

/// The drum pad, shown above the transport while a drum track is armed.
/// Pads fire on touch-down (not release) so they feel immediate, and
/// several can be played at once. Recording records the hits, not the mic.
struct DrumPadPanel: View {
    @Bindable var model: ProjectViewModel

    private var index: Int { model.armedTrack }
    private var track: Track { model.project.tracks[index] }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Kit", selection: Binding(get: { track.drumKit }, set: { model.setDrumKit(index, $0) })) {
                ForEach(DrumKit.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(model.isRecording)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<DrumKit.padCount, id: \.self) { pad in
                    DrumPad(
                        name: track.drumKit.padNames[pad],
                        color: DrumPadPanel.color(kit: track.drumKit, pad: pad)
                    ) {
                        model.hitPad(pad)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    /// Each kit has its own palette so the three feel distinct at a glance.
    static func color(kit: DrumKit, pad: Int) -> Color {
        let hues: [Double]
        switch kit {
        case .studio: hues = [0.58, 0.60, 0.52, 0.52, 0.62, 0.64, 0.50, 0.48]
        case .eightOhEight: hues = [0.92, 0.88, 0.84, 0.80, 0.80, 0.08, 0.95, 0.90]
        case .handPercussion: hues = [0.08, 0.10, 0.12, 0.13, 0.06, 0.15, 0.17, 0.11]
        }
        return Color(hue: hues[pad], saturation: 0.55, brightness: 0.85)
    }
}

/// One pad. Lights up and gives a light haptic on each hit.
struct DrumPad: View {
    let name: String
    let color: Color
    let onHit: () -> Void
    @State private var pressed = false
    @State private var flash = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(color.opacity(flash ? 0.95 : 0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(color.opacity(0.8), lineWidth: 1)
            )
            .overlay(
                Text(name)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .padding(4)
            )
            .frame(height: 64)
            .scaleEffect(pressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        onHit()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        flash = true
                        withAnimation(.easeOut(duration: 0.25)) { flash = false }
                    }
                    .onEnded { _ in pressed = false }
            )
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onHit() }
    }
}
