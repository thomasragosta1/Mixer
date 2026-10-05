import AVFoundation
import FourTrackCore

/// The four-track engine for one open project:
///
///     inputNode ──tap──> RecordingSink (scratch file for the armed track)
///     TrackChain 1...4 -> MasterChain (mixer -> limiter) -> mainMixer -> output
///     Metronome --------------------------------------> mainMixer
///
/// The graph is built once per project open; only parameters change while
/// playing. All methods run on the main actor except the tap callbacks.
@MainActor
final class MixerEngine {
    enum State: Equatable {
        case stopped
        case playing
        case recording
    }

    private(set) var engine = AVAudioEngine()
    private(set) var chains: [TrackChain] = (0..<Project.trackCount).map { TrackChain(index: $0) }
    private(set) var master = MasterChain()
    private(set) var metronome = Metronome()
    private(set) var pads = PadSampler()
    let meters = MeterStore()

    private(set) var state: State = .stopped
    /// Timeline frame and host time that playback started from.
    private var startFrame: Int64 = 0
    private var startHost: UInt64 = 0
    private var inputPrepared = false
    private var configObserver: NSObjectProtocol?
    private var metersInstalled = false

    private(set) var recordingSink: RecordingSink?
    private(set) var recordingPlan: RecordingPlan?

    /// Called before and after the engine reconnects for a hardware
    /// configuration change.
    var onWillReconfigure: (() -> Void)?
    var onConfigurationChange: (() -> Void)?

    var voiceProcessingEnabled = false

    /// How far ahead of "now" to start players, so all four start together.
    static let startLead = 0.05

    init() {
        build()
    }

    // MARK: Graph

    private func build() {
        chains.forEach { $0.attach(to: engine) }
        master.attach(to: engine)
        metronome.attach(to: engine)
        pads.attach(to: engine)
        connectGraph()
        engine.prepare()
        observeConfigurationChanges()
    }

    private func connectGraph() {
        chains.forEach { $0.connect(in: engine) }
        master.connect(tracks: chains, in: engine)
        metronome.connect(in: engine)
        pads.connect(to: chains[pads.routedTrack], in: engine)
    }

    private func observeConfigurationChanges() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleConfigurationChange()
            }
        }
    }

    /// Hardware format changed (route switch, sample rate change). The engine
    /// has stopped itself; reconnect and restart, keeping parameters and files.
    private func handleConfigurationChange() {
        // The notification arrives asynchronously; if the engine was already
        // restarted (e.g. by enabling the input for the first recording), the
        // graph is live and there is nothing to repair.
        guard !engine.isRunning else { return }
        // Let the owner finalize any recording while the scratch file is intact.
        onWillReconfigure?()
        stopPlayers()
        removeInputTap()
        let hadMeters = metersInstalled
        removeMeterTaps()
        engine.stop()
        for node in ownNodes {
            engine.disconnectNodeOutput(node)
        }
        connectGraph()
        engine.prepare()
        try? engine.start()
        if hadMeters { installMeterTaps() }
        state = .stopped
        onConfigurationChange?()
    }

    private var ownNodes: [AVAudioNode] {
        chains.flatMap(\.nodes) + [master.mixer, master.limiter, metronome.player] + pads.nodes
    }

    /// Throws away the whole engine (media services reset) and rebuilds it.
    func rebuild() {
        teardown()
        engine = AVAudioEngine()
        chains = (0..<Project.trackCount).map { TrackChain(index: $0) }
        master = MasterChain()
        metronome = Metronome()
        let kit = pads.kit
        let padSettings = pads.padSettings
        let routed = pads.routedTrack
        pads = PadSampler()
        pads.routedTrack = routed
        if let kit { pads.load(kit: kit, pads: padSettings) }
        inputPrepared = false
        build()
    }

    func teardown() {
        removeInputTap()
        removeMeterTaps()
        chains.forEach { $0.stop() }
        metronome.stop()
        engine.stop()
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        state = .stopped
    }

    func startIfNeeded() throws {
        if !AudioSessionManager.shared.isConfigured {
            try AudioSessionManager.shared.configure()
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    // MARK: Project state

    func load(project: Project, store: ProjectStore) {
        for chain in chains {
            let track = project.tracks[chain.index]
            let audio = track.audioFileName.map { store.fileURL($0, in: project.id) }
            let cleaned = track.cleanedFileName.map { store.fileURL($0, in: project.id) }
            chain.load(audioURL: audio, cleanedURL: cleaned)
        }
    }

    func apply(project: Project, warmthEnabled: Bool) {
        for chain in chains {
            chain.apply(project.tracks[chain.index], audible: project.isAudible(chain.index), warmthEnabled: warmthEnabled)
        }
        master.apply(masterVolume: project.masterVolume)
    }

    // MARK: Transport

    /// Current playhead in seconds while playing or recording.
    var currentSeconds: Double {
        guard state != .stopped else { return Double(startFrame) / EngineFormat.sampleRate }
        let now = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        let start = AVAudioTime.seconds(forHostTime: startHost)
        return Double(startFrame) / EngineFormat.sampleRate + max(0, now - start)
    }

    /// The timeline position at which the transport started, and the host time
    /// (in seconds) it is rendered, for smooth UI interpolation.
    var timelineAnchor: (seconds: Double, hostSeconds: Double) {
        (Double(startFrame) / EngineFormat.sampleRate, AVAudioTime.seconds(forHostTime: startHost))
    }

    /// Plays every track with audio after `seconds`.
    func play(from seconds: Double, metronome settings: MetronomeSettings?) throws {
        try startIfNeeded()
        stopPlayers()
        startFrame = frame(seconds)
        startHost = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: MixerEngine.startLead)
        let time = AVAudioTime(hostTime: startHost)
        for chain in chains where chain.schedule(from: startFrame) {
            chain.play(at: time)
        }
        if let settings, settings.enabled {
            metronome.start(fromFrame: startFrame, at: startHost, settings: settings)
        }
        state = .playing
    }

    /// Plays the click on its own (no tracks), from beat 1, to try a tempo.
    /// Returns the host time (seconds) of the first click.
    @discardableResult
    func startClickPreview(settings: MetronomeSettings) throws -> Double {
        try startIfNeeded()
        let host = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: MixerEngine.startLead)
        metronome.start(fromFrame: 0, at: host, settings: settings)
        return AVAudioTime.seconds(forHostTime: host)
    }

    /// Starts the click mid-song or mid-take, in time with what's playing
    /// (the metronome was switched on after play or record was pressed).
    func startClickLive(settings: MetronomeSettings) {
        guard state != .stopped else { return }
        let host = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: MixerEngine.startLead)
        let elapsed = AVAudioTime.seconds(forHostTime: host) - AVAudioTime.seconds(forHostTime: startHost)
        metronome.start(fromFrame: startFrame + frame(elapsed), at: host, settings: settings)
    }

    func stopClick() {
        metronome.stop()
    }

    func stopClickPreview() {
        metronome.stop()
    }

    /// Stops playback and returns where it stopped.
    @discardableResult
    func pause() -> Double {
        let position = currentSeconds
        stopPlayers()
        startFrame = frame(position)
        state = .stopped
        return position
    }

    func seek(to seconds: Double) {
        startFrame = frame(seconds)
    }

    private func stopPlayers() {
        chains.forEach { $0.stop() }
        metronome.stop()
    }

    // MARK: Drum pads

    /// Sends the pads through a drum track's chain so they sound like the track.
    func routePads(to trackIndex: Int, kit: DrumKit, pads padSettings: [PadSettings]) {
        pads.load(kit: kit, pads: padSettings)
        guard pads.routedTrack != trackIndex else { return }
        pads.routedTrack = trackIndex
        engine.disconnectNodeOutput(pads.mixer)
        pads.connect(to: chains[trackIndex], in: engine)
    }

    func hitPad(_ pad: Int, velocity: Float) throws {
        try startIfNeeded()
        pads.trigger(pad, velocity: velocity)
    }

    /// Output-side delay: a pad tapped in time with what the player hears
    /// lands this much earlier on the timeline than the engine clock says.
    var padTimingCompensation: Double {
        engine.outputNode.presentationLatency + AudioSessionManager.shared.ioBufferDuration
    }

    /// Starts a drum take: like a recording but with no microphone. Other
    /// audible tracks play for monitoring; hits are collected by the caller.
    func startDrumTake(trackIndex: Int, from seconds: Double, project: Project, metronome settings: MetronomeSettings?) throws {
        stopPlayers()
        try startIfNeeded()
        var countIn = 0.0
        if let settings, settings.enabled, settings.countInBars > 0 {
            countIn = Double(ClickTrack.countInFrames(bars: settings.countInBars, bpm: settings.bpm, beatsPerBar: settings.beatsPerBar)) / EngineFormat.sampleRate
        }
        startFrame = frame(seconds)
        startHost = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: MixerEngine.startLead + countIn)
        let time = AVAudioTime(hostTime: startHost)
        for chain in chains where chain.index != trackIndex && project.isAudible(chain.index) {
            if chain.schedule(from: startFrame) {
                chain.play(at: time)
            }
        }
        if let settings, settings.enabled {
            let countInFrames = frame(countIn)
            metronome.start(fromFrame: startFrame - countInFrames, at: startHost - AVAudioTime.hostTime(forSeconds: countIn), settings: settings)
        }
        recordingSink = nil
        recordingPlan = nil
        state = .recording
    }

    /// Ends a drum take; returns the timeline position it stopped at.
    func stopDrumTake() -> Double {
        let stopSeconds = currentSeconds
        stopPlayers()
        startFrame = frame(stopSeconds)
        state = .stopped
        return stopSeconds
    }

    // MARK: Recording

    /// Starts recording onto `trackIndex` from `seconds`, with every other
    /// audible track playing for monitoring. With a count-in, the click starts
    /// `countInBars` early and recording proper begins on the playhead.
    func startRecording(
        trackIndex: Int,
        from seconds: Double,
        project: Project,
        scratchURL: URL,
        latency: Double,
        route: AudioRouteKind,
        metronome settings: MetronomeSettings?
    ) throws -> RecordingPlan {
        stopPlayers()
        // The session must be .playAndRecord before the input node is created.
        if !AudioSessionManager.shared.isConfigured {
            try AudioSessionManager.shared.configure()
        }
        try prepareInput()
        try startIfNeeded()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInput
        }
        let sink = try RecordingSink(url: scratchURL, inputFormat: inputFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
            sink.append(buffer, at: time)
        }

        var countIn = 0.0
        if let settings, settings.enabled, settings.countInBars > 0 {
            countIn = Double(ClickTrack.countInFrames(bars: settings.countInBars, bpm: settings.bpm, beatsPerBar: settings.beatsPerBar)) / EngineFormat.sampleRate
        }

        startFrame = frame(seconds)
        startHost = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: MixerEngine.startLead + countIn)
        let time = AVAudioTime(hostTime: startHost)
        for chain in chains where chain.index != trackIndex && project.isAudible(chain.index) {
            if chain.schedule(from: startFrame) {
                chain.play(at: time)
            }
        }
        if let settings, settings.enabled {
            let countInFrames = frame(countIn)
            let clickHost = startHost - AVAudioTime.hostTime(forSeconds: countIn)
            metronome.start(fromFrame: startFrame - countInFrames, at: clickHost, settings: settings)
        }

        let plan = RecordingPlan(
            trackIndex: trackIndex,
            startFrame: startFrame,
            startHostTime: startHost,
            latency: latency,
            route: route,
            inputGainDB: project.tracks[trackIndex].inputGainDB
        )
        recordingSink = sink
        recordingPlan = plan
        state = .recording
        return plan
    }

    /// Punch-in: starts recording onto `trackIndex` while the song is already
    /// playing, without stopping or restarting anything. Recording begins at
    /// the current playback position; the other tracks and the click keep
    /// going. Returns nil when that isn't possible (not playing, or the
    /// microphone hasn't been set up yet; setting it up briefly stops the
    /// engine), and the caller then starts a normal recording from here.
    func punchInRecording(trackIndex: Int, scratchURL: URL, latency: Double, route: AudioRouteKind, inputGainDB: Double) throws -> RecordingPlan? {
        guard state == .playing, inputPrepared, engine.isRunning else { return nil }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { return nil }
        let sink = try RecordingSink(url: scratchURL, inputFormat: inputFormat)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
            sink.append(buffer, at: time)
        }
        // The punch point on the running timeline. Audio that arrives a little
        // later is placed where it really happened (see RecordingPlan.placement).
        let punchHost = max(mach_absolute_time(), startHost)
        let elapsed = AVAudioTime.seconds(forHostTime: punchHost) - AVAudioTime.seconds(forHostTime: startHost)
        let punchFrame = startFrame + frame(elapsed)
        // The track being recorded goes quiet; everything else keeps playing.
        chains[trackIndex].stop()
        let plan = RecordingPlan(
            trackIndex: trackIndex,
            startFrame: punchFrame,
            startHostTime: punchHost,
            latency: latency,
            route: route,
            inputGainDB: inputGainDB
        )
        recordingSink = sink
        recordingPlan = plan
        state = .recording
        return plan
    }

    /// Punch-in for a drum track: hits start recording now, nothing restarts.
    /// Returns the timeline position the take starts at, or nil if not playing.
    func punchInDrums(trackIndex: Int) -> Double? {
        guard state == .playing else { return nil }
        chains[trackIndex].stop()
        recordingSink = nil
        recordingPlan = nil
        state = .recording
        return currentSeconds
    }

    /// True once the count-in (if any) is over and the take is running.
    var isPastCountIn: Bool {
        state == .recording && mach_absolute_time() >= startHost
    }

    /// Stops capture and playback. Returns the finished scratch recording for
    /// splicing, or nil if nothing was recording.
    func stopRecording() -> (sink: RecordingSink, plan: RecordingPlan, stopSeconds: Double)? {
        guard state == .recording, let sink = recordingSink, let plan = recordingPlan else { return nil }
        let stopSeconds = currentSeconds
        removeInputTap()
        stopPlayers()
        try? sink.finish()
        recordingSink = nil
        recordingPlan = nil
        startFrame = frame(stopSeconds)
        state = .stopped
        return (sink, plan, stopSeconds)
    }

    private func removeInputTap() {
        if inputPrepared {
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    /// The input node is enabled lazily on the first recording so playback
    /// alone never turns on the microphone.
    private func prepareInput() throws {
        guard !inputPrepared else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        let input = engine.inputNode
        if voiceProcessingEnabled {
            try? input.setVoiceProcessingEnabled(true)
        }
        inputPrepared = true
        engine.prepare()
        if wasRunning { try engine.start() }
    }

    /// Applies a Developer Mode change to echo cancellation; takes effect on the
    /// next recording.
    func setVoiceProcessing(_ enabled: Bool) {
        voiceProcessingEnabled = enabled
        guard inputPrepared, state == .stopped else { return }
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        try? engine.inputNode.setVoiceProcessingEnabled(enabled)
        engine.prepare()
        if wasRunning { try? engine.start() }
    }

    // MARK: Latency

    /// Spec formula, using the engine's own view of IO latency.
    var estimatedLatency: Double {
        let session = AudioSessionManager.shared
        let inLatency = inputPrepared ? engine.inputNode.presentationLatency : session.inputLatency
        return LatencyModel.estimate(
            inputLatency: inLatency,
            outputLatency: engine.outputNode.presentationLatency,
            ioBufferDuration: session.ioBufferDuration
        )
    }

    // MARK: Meters (Developer Mode)

    func setMetersEnabled(_ enabled: Bool) {
        if enabled { installMeterTaps() } else { removeMeterTaps() }
    }

    private func installMeterTaps() {
        guard !metersInstalled else { return }
        metersInstalled = true
        let store = meters
        for chain in chains {
            let index = chain.index
            chain.trackMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                store.update(index: index, buffer: buffer)
            }
        }
        master.limiter.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            store.update(index: MeterStore.masterIndex, buffer: buffer)
        }
    }

    private func removeMeterTaps() {
        guard metersInstalled else { return }
        metersInstalled = false
        chains.forEach { $0.trackMixer.removeTap(onBus: 0) }
        master.limiter.removeTap(onBus: 0)
        meters.reset()
    }

    // MARK: Helpers

    private func frame(_ seconds: Double) -> Int64 {
        Int64((max(0, seconds) * EngineFormat.sampleRate).rounded())
    }
}

enum RecorderError: LocalizedError {
    case noInput
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noInput: return "No microphone is available."
        case .permissionDenied: return "Microphone access is off."
        }
    }
}

/// Peak and RMS levels per track plus master, written from tap threads and
/// read by the UI.
final class MeterStore: @unchecked Sendable {
    static let masterIndex = Project.trackCount

    struct Level: Equatable {
        var peak: Float = 0
        var rms: Float = 0
        /// Sticky until reset by tapping the meter.
        var clipped = false
    }

    private let lock = NSLock()
    private var levels = [Level](repeating: Level(), count: Project.trackCount + 1)

    func update(index: Int, buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        var peak: Float = 0
        var sum: Float = 0
        for ch in 0..<channels {
            let p = data[ch]
            for i in 0..<frames {
                let v = abs(p[i])
                if v > peak { peak = v }
                sum += v * v
            }
        }
        let rms = frames > 0 ? (sum / Float(frames * max(channels, 1))).squareRoot() : 0
        lock.withLock {
            var level = levels[index]
            // Fast attack, ~300 ms fall at 1024-frame buffers.
            level.peak = max(peak, level.peak * 0.8)
            level.rms = max(rms, level.rms * 0.8)
            if peak >= 0.999 { level.clipped = true }
            levels[index] = level
        }
    }

    func snapshot() -> [Level] {
        lock.withLock { levels }
    }

    func resetClip(index: Int) {
        lock.withLock { levels[index].clipped = false }
    }

    func reset() {
        lock.withLock { levels = [Level](repeating: Level(), count: Project.trackCount + 1) }
    }
}
