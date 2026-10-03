import SwiftUI
import FourTrackCore

/// Scrolling waveform with the playhead fixed at the horizontal center, like
/// Voice Memos. Draws cached peaks (one per 10 ms) as rounded bars, and
/// overlays the take in progress while recording.
struct WaveformView: View {
    let peaks: [Float]
    var livePeaks: [Float] = []
    var liveStart: Double = 0
    var showsLive = false
    let playhead: Double
    var pointsPerSecond: CGFloat = WaveformView.defaultPointsPerSecond
    var color: Color = .primary
    var liveColor: Color = .red

    static let defaultPointsPerSecond: CGFloat = 50
    static let peaksPerSecond = CAFFormat.defaultSampleRate / Double(PeakGenerator.framesPerPeak)
    static let barWidth: CGFloat = 2
    static let barSpacing: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            let maxBar = size.height * 0.9
            let liveEnd = liveStart + Double(livePeaks.count) / WaveformView.peaksPerSecond
            var x: CGFloat = (size.width / 2).truncatingRemainder(dividingBy: WaveformView.barSpacing)
            while x < size.width {
                let t0 = playhead + Double((x - size.width / 2) / pointsPerSecond)
                let t1 = t0 + Double(WaveformView.barSpacing / pointsPerSecond)
                if t1 > 0 {
                    let inLive = showsLive && t0 >= liveStart && t0 < liveEnd
                    let level: Float
                    if inLive {
                        level = Self.peak(in: livePeaks, from: t0 - liveStart, to: t1 - liveStart)
                    } else if showsLive && t0 >= liveStart && t0 < max(liveEnd, playhead) {
                        // Region being replaced but not drawn yet: blank.
                        level = 0
                    } else {
                        level = Self.peak(in: peaks, from: t0, to: t1)
                    }
                    if level > 0 {
                        // Gentle curve so quiet material is still visible.
                        let h = max(2, CGFloat(pow(Double(level), 0.6)) * maxBar)
                        let rect = CGRect(x: x - WaveformView.barWidth / 2, y: mid - h / 2, width: WaveformView.barWidth, height: h)
                        let played = t0 < playhead
                        let base = inLive ? liveColor : color
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(base.opacity(played ? 0.9 : 0.45)))
                    }
                }
                x += WaveformView.barSpacing
            }
            // Baseline so empty stretches still read as a track.
            var line = Path()
            line.move(to: CGPoint(x: 0, y: mid))
            line.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(line, with: .color(color.opacity(0.12)), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    /// Max of the peaks covering [from, to) seconds.
    static func peak(in peaks: [Float], from: Double, to: Double) -> Float {
        guard !peaks.isEmpty else { return 0 }
        let a = max(0, Int(from * peaksPerSecond))
        let b = min(peaks.count, max(a + 1, Int(to * peaksPerSecond)))
        guard a < b else { return 0 }
        var m: Float = 0
        for i in a..<b where peaks[i] > m { m = peaks[i] }
        return m
    }
}
