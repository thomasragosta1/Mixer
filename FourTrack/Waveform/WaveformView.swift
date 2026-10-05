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

    /// Like `position` but runs negative before the transport reaches its
    /// start, so a count-in's beats can be shown.
    func rawPosition(at now: Date) -> Double {
        running ? seconds + now.timeIntervalSince(date) : seconds
    }
}

/// The metronome's beat grid, drawn as faint lines behind the waveforms.
struct BeatGrid: Equatable {
    var bpm: Double
    var beatsPerBar: Int
    /// Beat number `anchorBeat` falls at timeline second `anchorSeconds`
    /// (the grid moves when the tempo changes while the click plays).
    var anchorSeconds: Double = 0
    var anchorBeat: Double = 0

    var secondsPerBeat: Double { 60 / max(1, bpm) }

    func time(ofBeat k: Double) -> Double { anchorSeconds + (k - anchorBeat) * secondsPerBeat }
    func beat(at seconds: Double) -> Double { anchorBeat + (seconds - anchorSeconds) / secondsPerBeat }
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
    /// When the metronome is on: bar lines (stronger) and beat lines behind the bars.
    var beatGrid: BeatGrid? = nil

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

        if let beatGrid {
            drawBeatLines(beatGrid, in: &context, size: size, anchorX: anchorX, playhead: playhead)
        }

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

    /// Hairlines on every beat, a little stronger on the first beat of each bar.
    /// Beat lines drop out when they'd be closer than 9 pt, so fast tempos stay calm.
    private func drawBeatLines(_ grid: BeatGrid, in context: inout GraphicsContext, size: CGSize, anchorX: CGFloat, playhead: Double) {
        let startT = playhead - Double(anchorX / pointsPerSecond)
        let endT = playhead + Double((size.width - anchorX) / pointsPerSecond)
        let first = grid.beat(at: startT).rounded(.up)
        let last = grid.beat(at: endT).rounded(.down)
        guard last >= first, last - first < 2_000 else { return }
        let showBeats = CGFloat(grid.secondsPerBeat) * pointsPerSecond >= 9
        let n = Double(max(1, grid.beatsPerBar))
        var bars = Path()
        var beats = Path()
        var k = first
        while k <= last {
            let x = anchorX + CGFloat(grid.time(ofBeat: k) - playhead) * pointsPerSecond
            let isBar = (k.truncatingRemainder(dividingBy: n) + n).truncatingRemainder(dividingBy: n) == 0
            if isBar {
                bars.addRect(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height))
            } else if showBeats {
                beats.addRect(CGRect(x: x - 0.25, y: size.height * 0.2, width: 0.5, height: size.height * 0.6))
            }
            k += 1
        }
        context.fill(beats, with: .color(color.opacity(0.10)))
        context.fill(bars, with: .color(color.opacity(0.22)))
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
