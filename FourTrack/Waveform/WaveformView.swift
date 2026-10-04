import SwiftUI
import FourTrackCore

/// Where the playhead is, as a reference point plus whether time is running,
/// so views can animate it at display refresh rate instead of the model's
/// update rate.
struct PlayheadClock: Equatable {
    var seconds: Double
    var date: Date
    var running: Bool

    func position(at now: Date) -> Double {
        running ? seconds + max(0, now.timeIntervalSince(date)) : seconds
    }
}

/// Voice Memos-style waveform: rounded bars on a fixed time grid that scroll
/// smoothly past an anchor. While recording the anchor sits at the right
/// edge, so the newest audio enters from the right and moves left. Otherwise
/// it sits at the center with a thin playhead line.
struct WaveformView: View {
    let peaks: [Float]
    var livePeaks: [Float] = []
    var liveStart: Double = 0
    var showsLive = false
    let clock: PlayheadClock
    /// 0...1 across the width: 0.5 for playback, 1 while recording.
    var anchor: CGFloat = 0.5
    var showsPlayheadLine = true
    var pointsPerSecond: CGFloat = WaveformView.defaultPointsPerSecond
    var color: Color = .primary

    static let defaultPointsPerSecond: CGFloat = 50
    static let peaksPerSecond = CAFFormat.defaultSampleRate / Double(PeakGenerator.framesPerPeak)
    static let barWidth: CGFloat = 2.5
    static let barSpacing: CGFloat = 4.5

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !clock.running)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, playhead: clock.position(at: timeline.date))
            }
        }
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, playhead: Double) {
        let mid = size.height / 2
        let maxBar = size.height * 0.88
        let anchorX = anchor >= 1 ? size.width - Self.barWidth : size.width * anchor
        let dt = Double(Self.barSpacing / pointsPerSecond)
        let liveEnd = liveStart + Double(livePeaks.count) / Self.peaksPerSecond

        // Bars sit on a fixed time grid, so they glide instead of shimmering.
        let firstK = Int(((playhead - Double(anchorX / pointsPerSecond)) / dt).rounded(.down))
        let lastK = Int(((playhead + Double((size.width - anchorX) / pointsPerSecond)) / dt).rounded(.up))
        guard lastK >= firstK else { return }

        var played = Path()
        var upcoming = Path()
        for k in max(0, firstK)...max(0, lastK) {
            let t0 = Double(k) * dt
            let t1 = t0 + dt
            let level: Float
            if showsLive && t0 >= liveStart {
                // The take in progress; nothing exists past what's been captured.
                guard t0 < liveEnd else { continue }
                level = Self.level(in: livePeaks, from: t0 - liveStart, to: t1 - liveStart)
            } else {
                guard t0 < Double(peaks.count) / Self.peaksPerSecond else { continue }
                level = Self.level(in: peaks, from: t0, to: t1)
            }
            let x = anchorX + CGFloat(t0 - playhead) * pointsPerSecond
            guard x > -Self.barWidth, x < size.width + Self.barWidth else { continue }
            // Gentle curve so quiet passages stay visible; silence is a dot.
            let h = max(Self.barWidth, CGFloat(pow(Double(level), 0.55)) * maxBar)
            let rect = CGRect(x: x - Self.barWidth / 2, y: mid - h / 2, width: Self.barWidth, height: h)
            let bar = Path(roundedRect: rect, cornerRadius: Self.barWidth / 2)
            if t0 < playhead {
                played.addPath(bar)
            } else {
                upcoming.addPath(bar)
            }
        }
        context.fill(played, with: .color(color.opacity(0.85)))
        context.fill(upcoming, with: .color(color.opacity(0.35)))

        if showsPlayheadLine {
            let line = CGRect(x: anchorX - 0.75, y: 0, width: 1.5, height: size.height)
            context.fill(Path(roundedRect: line, cornerRadius: 0.75), with: .color(.accentColor))
        }
    }

    /// Mix of peak and average over [from, to) seconds: keeps transients
    /// readable without the spiky look of raw peaks.
    static func level(in peaks: [Float], from: Double, to: Double) -> Float {
        guard !peaks.isEmpty else { return 0 }
        let a = max(0, Int(from * peaksPerSecond))
        let b = min(peaks.count, max(a + 1, Int(to * peaksPerSecond)))
        guard a < b else { return 0 }
        var m: Float = 0
        var sum: Float = 0
        for i in a..<b {
            m = max(m, peaks[i])
            sum += peaks[i]
        }
        let mean = sum / Float(b - a)
        return min(1, 0.6 * m + 0.4 * mean)
    }
}
