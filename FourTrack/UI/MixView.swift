import SwiftUI
import FourTrackCore

/// Mixing mode: one track per page, swipe (or tap the arrows) to change
/// track. The current track and a compact transport stay pinned at the top
/// so you can play and rewind while adjusting; the controls below are
/// native-style horizontal sliders in grouped sections.
struct MixView: View {
    @Bindable var model: ProjectViewModel
    @State private var advancedTrack: Int?

    /// Page ids: track indices in lane order, plus the master page in Developer Mode.
    static let masterPage = -1
    private var pages: [Int] {
        model.visibleLanes + (model.developerMode ? [Self.masterPage] : [])
    }

    private var currentPage: Int {
        pages.contains(model.mixPage) ? model.mixPage : (pages.first ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            pinnedHeader
            Divider()
            TabView(selection: Binding(get: { currentPage }, set: { model.mixPage = $0 })) {
                ForEach(pages, id: \.self) { page in
                    Group {
                        if page == Self.masterPage {
                            MasterMixPage(model: model)
                        } else {
                            TrackMixPage(model: model, index: page) { advancedTrack = page }
                        }
                    }
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: currentPage)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(item: Binding(
            get: { advancedTrack.map(TrackID.init) },
            set: { advancedTrack = $0?.id }
        )) { item in
            DevTrackControlsView(model: model, index: item.id)
        }
    }

    // MARK: Pinned header

    private var pinnedHeader: some View {
        VStack(spacing: 10) {
            pager
            if currentPage == Self.masterPage {
                MasterSummaryCard(model: model)
            } else {
                CompactTrackCard(model: model, index: currentPage)
            }
            CompactTransport(model: model)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Color(uiColor: .systemGroupedBackground))
        // Swiping the header pages too, so the gesture works everywhere above the sliders.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { g in
                    guard abs(g.translation.width) > abs(g.translation.height) else { return }
                    step(g.translation.width < 0 ? 1 : -1)
                }
        )
    }

    /// "‹  Track 2  ›" with page dots: makes the swipe discoverable.
    private var pager: some View {
        let position = pages.firstIndex(of: currentPage) ?? 0
        return HStack {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .disabled(position == 0)
            .accessibilityLabel("Previous track")

            Spacer(minLength: 0)
            VStack(spacing: 5) {
                Text(title(for: currentPage))
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, _ in
                        Circle()
                            .fill(i == position ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(position + 1) of \(pages.count)")
            Spacer(minLength: 0)

            Button { step(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .disabled(position >= pages.count - 1)
            .accessibilityLabel("Next track")
        }
        .buttonStyle(.borderless)
    }

    private func title(for page: Int) -> String {
        page == Self.masterPage ? "Master" : model.project.tracks[page].name
    }

    private func step(_ delta: Int) {
        guard let i = pages.firstIndex(of: currentPage) else { return }
        let next = min(max(0, i + delta), pages.count - 1)
        guard next != i else { return }
        withAnimation(.easeInOut(duration: 0.25)) { model.mixPage = pages[next] }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private struct TrackID: Identifiable {
        let id: Int
    }
}

// MARK: - Pinned pieces

/// Smaller version of the record-mode card: name, M/S and the waveform.
/// Drag the waveform sideways to scrub.
struct CompactTrackCard: View {
    @Bindable var model: ProjectViewModel
    let index: Int
    @State private var scrubStart: Double?

    private var track: Track { model.project.tracks[index] }

    var body: some View {
        HStack(spacing: 10) {
            ToggleChip(title: "S", isOn: track.solo, onColor: .yellow, accessibilityName: "Solo \(track.name)") {
                model.toggleSolo(index)
            }
            WaveformView(
                peaks: model.peaks[index],
                clock: model.clock,
                color: model.project.isAudible(index) ? .primary : .secondary
            )
            .overlay {
                if track.isEmpty {
                    Text("Empty").font(.caption).foregroundStyle(.secondary)
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous).fill(Color(uiColor: .tertiarySystemFill).opacity(0.5)))
            .clipShape(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
            .contentShape(Rectangle())
            .highPriorityGesture(scrub)
        }
        .padding(10)
        .frame(height: 60)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { g in
                if scrubStart == nil {
                    scrubStart = model.playhead
                    model.beginScrub()
                }
                model.scrub(to: (scrubStart ?? 0) - Double(g.translation.width / WaveformView.defaultPointsPerSecond))
            }
            .onEnded { _ in
                scrubStart = nil
                model.endScrub()
            }
    }
}

/// Master page header: overall level (Developer Mode).
struct MasterSummaryCard: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(.secondary)
            Text("All tracks")
                .font(.subheadline.weight(.semibold))
            Spacer()
            HorizontalMeter(level: model.meterLevels[MeterStore.masterIndex]) {
                model.resetClip(MeterStore.masterIndex)
            }
            .frame(width: 120)
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

/// One-line transport for mixing: time, return to start, back/forward 15 s, play/pause.
struct CompactTransport: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        HStack(spacing: 0) {
            Text(TimeFormat.precise(model.playhead))
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
                .accessibilityLabel("Playhead")
                .accessibilityValue(TimeFormat.duration(model.playhead))
            Spacer(minLength: 0)
            button("backward.end.fill", "Return to start") { model.returnToStart() }
            button("gobackward.15", "Skip back 15 seconds") { model.skip(by: -15) }
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 52, height: 44)
            }
            .disabled(!model.hasAnyAudio)
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            button("goforward.15", "Skip forward 15 seconds") { model.skip(by: 15) }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
    }

    private func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Pages

/// All controls for one track, as native-style horizontal sliders.
struct TrackMixPage: View {
    @Bindable var model: ProjectViewModel
    let index: Int
    let onAdvanced: () -> Void

    private var track: Track { model.project.tracks[index] }
    private var name: String { track.name }

    var body: some View {
        List {
            if track.isDrums {
                Section {
                    DrumKitPicker(kit: track.drumKit) { model.setDrumKit(index, $0) }
                        .disabled(model.isRecording)
                        .padding(.vertical, 4)
                } header: {
                    Text("Drum Kit")
                } footer: {
                    Text(track.drumKit.isStudio
                         ? "Tight is dry and punchy; Roomy keeps the sound of the room. Changing either re-plays every hit on this track."
                         : "Changing the kit re-plays every hit on this track with the new sounds.")
                }
            } else {
            Section {
                Toggle(isOn: Binding(
                    get: { track.isCleanupOn },
                    set: { _ in model.toggleCleanup(index) }
                )) {
                    HStack {
                        Text("Clean Up")
                        if let progress = model.cleanupProgress[index] {
                            ProgressView(value: progress)
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .padding(.leading, 4)
                        }
                    }
                }
                .disabled(track.isEmpty)
                if track.isCleanupOn {
                    SliderRow(title: "Amount", value: percent(track.cleanup)) {
                        MacroSlider(label: "\(name) Clean up amount", value: Binding(
                            get: { track.cleanup },
                            set: { model.setCleanup(index, $0) }
                        ), defaultValue: Track.defaultCleanupLevel)
                    }
                }
            } footer: {
                Text("Reduces background noise, harsh \"s\" sounds and room echo. Works best on voice.")
            }
            }

            Section("Tone") {
                eqRow("High", value: track.eqHigh) { model.setEQ(index, high: $0) }
                eqRow("Mid", value: track.eqMid) { model.setEQ(index, mid: $0) }
                eqRow("Low", value: track.eqLow) { model.setEQ(index, low: $0) }
            }

            Section("Character") {
                SliderRow(title: "Compressor", value: track.isCompressorCustom ? "Custom" : percent(track.compressor)) {
                    MacroSlider(label: "\(name) Compressor", value: Binding(
                        get: { track.compressor },
                        set: { model.setCompressor(index, $0) }
                    ), defaultValue: Track.defaultCompressor, isCustom: track.isCompressorCustom)
                }
                SliderRow(title: "Space", value: track.isSpaceCustom ? "Custom" : percent(track.space)) {
                    MacroSlider(label: "\(name) Space", value: Binding(
                        get: { track.space },
                        set: { model.setSpace(index, $0) }
                    ), isCustom: track.isSpaceCustom)
                }
                if model.developerMode && model.settings.warmthEnabled {
                    SliderRow(title: "Warmth", value: percent(track.warmth)) {
                        MacroSlider(label: "\(name) Warmth", value: Binding(
                            get: { track.warmth },
                            set: { model.setWarmth(index, $0) }
                        ))
                    }
                }
            }

            Section("Level") {
                SliderRow(title: "Volume", value: SliderSpeech.shortDB(MacroCurves.volumeDB(track.volume))) {
                    VolumeFader(label: "\(name) Volume", value: Binding(
                        get: { track.volume },
                        set: { model.setVolume(index, $0) }
                    ))
                }
                if model.developerMode {
                    HorizontalMeter(level: model.meterLevels[index]) { model.resetClip(index) }
                        .frame(height: 22)
                }
            }

            if model.developerMode {
                Section {
                    Button("Advanced Controls…", action: onAdvanced)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
    }

    private func eqRow(_ title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        SliderRow(title: title, value: track.isEQCustom ? "Custom" : SliderSpeech.shortDB(MacroCurves.eqGainDB(value))) {
            CenteredSlider(label: "\(name) \(title)", value: Binding(get: { value }, set: set), dimmed: track.isEQCustom)
        }
    }

    private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}

/// Master volume (Developer Mode).
struct MasterMixPage: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        List {
            Section {
                SliderRow(title: "Master Volume", value: SliderSpeech.shortDB(MacroCurves.volumeDB(model.project.masterVolume))) {
                    VolumeFader(label: "Master volume", value: Binding(
                        get: { model.project.masterVolume },
                        set: { model.setMasterVolume($0) }
                    ))
                }
                HorizontalMeter(level: model.meterLevels[MeterStore.masterIndex]) {
                    model.resetClip(MeterStore.masterIndex)
                }
                .frame(height: 22)
            } footer: {
                Text("A limiter on the master keeps the mix from clipping.")
            }
        }
        .listStyle(.insetGrouped)
    }
}

/// Settings-style row: title and value on one line, slider underneath.
struct SliderRow<Slider: View>: View {
    let title: String
    let value: String
    @ViewBuilder let slider: () -> Slider

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityHidden(true)
            slider()
        }
        .padding(.vertical, 2)
    }
}

/// Peak/RMS level bar with a sticky clip light (tap to reset).
struct HorizontalMeter: View {
    let level: MeterStore.Level
    let onResetClip: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .tertiarySystemFill))
                    Capsule()
                        .fill(gradient)
                        .frame(width: geo.size.width * Self.fraction(level.peak))
                        .opacity(0.35)
                    Capsule()
                        .fill(gradient)
                        .frame(width: geo.size.width * Self.fraction(level.rms))
                }
            }
            .frame(height: 6)
            Circle()
                .fill(level.clipped ? Color.red : Color(uiColor: .tertiarySystemFill))
                .frame(width: 8, height: 8)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onResetClip)
        .accessibilityElement()
        .accessibilityLabel("Level")
        .accessibilityValue(level.clipped ? "Clipped" : SliderSpeech.decibels(MacroCurves.gainToDB(Double(level.peak))))
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: [.green, .green, .yellow, .red], startPoint: .leading, endPoint: .trailing)
    }

    /// -60...0 dBFS mapped to 0...1.
    static func fraction(_ amplitude: Float) -> CGFloat {
        guard amplitude > 0 else { return 0 }
        let db = 20 * log10(Double(amplitude))
        return CGFloat(min(1, max(0, (db + 60) / 60)))
    }
}
