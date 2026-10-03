import SwiftUI
import UIKit

enum SliderAxis {
    case horizontal
    case vertical
}

enum SliderMetrics {
    static let trackThickness: CGFloat = 4
    static let thumbDiameter: CGFloat = 28
    /// Minimum touch target in both directions.
    static let hitTarget: CGFloat = 44
}

/// Shared mechanics for every slider in the app: Voice Memos-style look
/// (thin gray track, blue fill, white round thumb), relative dragging so a
/// touch never makes the value jump, magnetic detents with a light haptic
/// tick, and double tap to reset.
struct SliderCore: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Where the fill starts: the low end for macros, the center for EQ.
    let fillOrigin: Double
    /// Values that attract the thumb and tick when crossed.
    var detents: [Double] = []
    /// Snap radius as a fraction of the range.
    var detentRadius: Double = 0.035
    let resetValue: Double
    var axis: SliderAxis = .horizontal
    var tint: Color = .accentColor
    var dimmed = false
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragStart: Double?
    @State private var lastHapticDetent: Double?
    @Environment(\.isEnabled) private var isEnabled

    private var span: Double { range.upperBound - range.lowerBound }

    var body: some View {
        GeometryReader { geo in
            let length = trackLength(in: geo.size)
            ZStack(alignment: axis == .horizontal ? .leading : .bottom) {
                track(in: geo.size)
                fill(in: geo.size, length: length)
                ForEach(detents.filter { $0 != fillOrigin }, id: \.self) { d in
                    tick(at: d, in: geo.size, length: length)
                }
                thumb(in: geo.size, length: length)
            }
            .contentShape(Rectangle())
            // High priority so vertical faders win over the mixer's scroll view.
            .highPriorityGesture(drag(length: length))
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                onEditingChanged(true)
                value = resetValue
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onEditingChanged(false)
            })
        }
        .frame(
            minWidth: axis == .vertical ? SliderMetrics.hitTarget : nil,
            minHeight: axis == .horizontal ? SliderMetrics.hitTarget : nil
        )
        .opacity(isEnabled ? 1 : 0.4)
    }

    // MARK: Geometry

    private func trackLength(in size: CGSize) -> CGFloat {
        max(1, (axis == .horizontal ? size.width : size.height) - SliderMetrics.thumbDiameter)
    }

    /// Distance of a value from the low end along the axis, thumb-center coordinates.
    private func offset(for v: Double, length: CGFloat) -> CGFloat {
        let t = span > 0 ? (min(max(v, range.lowerBound), range.upperBound) - range.lowerBound) / span : 0
        return CGFloat(t) * length + SliderMetrics.thumbDiameter / 2
    }

    private func track(in size: CGSize) -> some View {
        Capsule()
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(
                width: axis == .horizontal ? size.width - SliderMetrics.thumbDiameter : SliderMetrics.trackThickness,
                height: axis == .horizontal ? SliderMetrics.trackThickness : size.height - SliderMetrics.thumbDiameter
            )
            .position(x: size.width / 2, y: size.height / 2)
    }

    private func fill(in size: CGSize, length: CGFloat) -> some View {
        let a = offset(for: fillOrigin, length: length)
        let b = offset(for: value, length: length)
        let lo = min(a, b), hi = max(a, b)
        return Capsule()
            .fill(tint.opacity(dimmed ? 0.45 : 1))
            .frame(
                width: axis == .horizontal ? max(hi - lo, 0) : SliderMetrics.trackThickness,
                height: axis == .horizontal ? SliderMetrics.trackThickness : max(hi - lo, 0)
            )
            .position(
                x: axis == .horizontal ? (lo + hi) / 2 : size.width / 2,
                y: axis == .horizontal ? size.height / 2 : size.height - (lo + hi) / 2
            )
    }

    private func tick(at d: Double, in size: CGSize, length: CGFloat) -> some View {
        let o = offset(for: d, length: length)
        return Rectangle()
            .fill(Color.secondary.opacity(0.6))
            .frame(width: axis == .horizontal ? 1.5 : 12, height: axis == .horizontal ? 12 : 1.5)
            .position(
                x: axis == .horizontal ? o : size.width / 2,
                y: axis == .horizontal ? size.height / 2 : size.height - o
            )
    }

    private func thumb(in size: CGSize, length: CGFloat) -> some View {
        let o = offset(for: value, length: length)
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1.5)
            .frame(width: SliderMetrics.thumbDiameter, height: SliderMetrics.thumbDiameter)
            .position(
                x: axis == .horizontal ? o : size.width / 2,
                y: axis == .horizontal ? size.height / 2 : size.height - o
            )
    }

    // MARK: Interaction

    private func drag(length: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                if dragStart == nil {
                    dragStart = value
                    onEditingChanged(true)
                }
                let travel = axis == .horizontal ? g.translation.width : -g.translation.height
                let raw = (dragStart ?? value) + Double(travel / length) * span
                let clamped = min(max(raw, range.lowerBound), range.upperBound)
                let snapped = snap(clamped)
                hapticIfCrossing(from: value, to: snapped)
                value = snapped
            }
            .onEnded { _ in
                dragStart = nil
                lastHapticDetent = nil
                onEditingChanged(false)
            }
    }

    private func snap(_ v: Double) -> Double {
        for d in detents where abs(v - d) <= detentRadius * span {
            return d
        }
        return v
    }

    private func hapticIfCrossing(from old: Double, to new: Double) {
        for d in detents {
            let crossed = (old < d && new >= d) || (old > d && new <= d)
            if crossed && lastHapticDetent != d {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                lastHapticDetent = d
                return
            }
            if new != d && lastHapticDetent == d {
                lastHapticDetent = nil
            }
        }
    }
}
