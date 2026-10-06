import AVFoundation
import Foundation
import Observation
import FourTrackCore

/// Drives one open project. The UI talks only to this; it talks to
/// `MixerEngine` and the `ProjectStore`.
@Observable
@MainActor
final class ProjectViewModel {
    // MARK: Published state

    private(set) var project: Project
    /// Cached waveform peaks per track (one per 10 ms).
    private(set) var peaks: [[Float]] = Array(repeating: [], count: Project.trackCount)
    /// Peaks of the take in progress, starting at `recordingStartSeconds`.
    private(set) var livePeaks: [Float] = []
    private(set) var recordingStartSeconds: Double = 0
    private(set) var playhead: Double = 0
    /// Smoothly animatable playhead for the waveforms.
    private(set) var clock = PlayheadClock(seconds: 0, date: Date(), running: false)
    private(set) var isPlaying = false
    private(set) var isRecording = false
    /// True during a count-in, before the take starts.
    private(set) var isCountingIn = false
    /// Undo / redo availability and what the next step is, for the toolbar.
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoLabel: String?
    private(set) var redoLabel: String?
    /// The metronome is playing on its own (its play button).
    private(set) var isPreviewingClick = false
    /// Beat-light clock for the click preview.
    private(set) var previewClock = PlayheadClock(seconds: 0, date: Date(), running: false)
    /// Splicing a finished take into its track.
    private(set) var isSaving = false
    var armedTrack = 0
    var mixMode = false {
        didSet {
            // Open Mixing on the armed track.
            if mixMode && !oldValue { mixPage = armedTrack }
        }
    }
    /// Track index shown in Mixing (or MixView.masterPage).
    var mixPage = 0

    /// Cleanup progress per track (nil = not running).
    private(set) var cleanupProgress: [Int: Double] = [:]

    var showPermissionDenied = false
    var showBluetoothTip = false
    /// One-time tip before the first audio recording with the click on the speaker.
    var showMetronomeHeadphoneTip = false
    var errorMessage: String?

    private(set) var meterLevels: [MeterStore.Level] = Array(repeating: .init(), count: Project.trackCount + 1)

    // Export
    private(set) var exportProgress: Double?
    var exportedURLs: [URL] = []

    // MARK: Dependencies

    let store: ProjectStore
    let settings: AppSettings
    private let engine: MixerEngine
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupJobs: [Int: ProgressBox] = [:]
    @ObservationIgnored private var pendingMarkerFinal = false
    @ObservationIgnored private var scrubWasPlaying = false
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private var isActive = false
    /// Guards against a double tap while permission or the engine is starting.
    @ObservationIgnored private var isStartingRecording = false
    // Drum takes
    @ObservationIgnored private var isDrumTake = false
    @ObservationIgnored private var drumTakeStart: Double = 0
    @ObservationIgnored private var drumTakeHits: [DrumHit] = []
    @ObservationIgnored private var padPeaksCache: [DrumKit: [[Float]]] = [:]
    @ObservationIgnored private var padRenderTask: Task<Void, Never>?
    @ObservationIgnored private lazy var history = UndoHistory(store: store, projectID: project.id)
    @ObservationIgnored private var tempoRestartTask: Task<Void, Never>?
    @ObservationIgnored private var drumRenderGeneration = [Int](repeating: 0, count: Project.trackCount)
    /// Bumped on every splice so a Cleanup render of an older take is discarded.
    @ObservationIgnored private var takeGeneration = [Int](repeating: 0, count: Project.trackCount)

    init(project: Project, store: ProjectStore, settings: AppSettings = .shared) {
        var project = project
        project.migrateSimpleMode()
        store.cleanTemporaryFiles(project: project.id)
        store.refreshDurations(&project)
        self.project = project
        self.store = store
        self.settings = settings
        self.engine = MixerEngine()
        playhead = min(project.playheadSeconds, project.durationSeconds)
        // Arm the first empty lane, or the last one if all have takes.
        armedTrack = project.visibleLanes.first(where: { project.tracks[$0].isEmpty }) ?? project.visibleLanes.last ?? 0
        engine.load(project: project, store: store)
        applyAll()
        loadPeaks()
        engine.seek(to: playhead)
        clock = PlayheadClock(seconds: playhead, date: Date(), running: false)
        routePadsIfNeeded()
        engine.onWillReconfigure = { [weak self] in self?.handleEngineWillReconfigure() }
        engine.onConfigurationChange = { [weak self] in self?.applyAll() }
    }

    /// Called when the project screen appears: takes over session events and
    /// recovers any take interrupted by a crash.
    func activate() {
        guard !isActive else { return }
        isActive = true
        AudioSessionManager.shared.onEvent = { [weak self] event in self?.handleSessionEvent(event) }
        recoverPendingRecording()
        developerModeChanged()
        // Drum takes from before choke groups: re-render once so repeated hits
        // stop piling up (the hits themselves are unchanged).
        for i in project.visibleLanes where project.tracks[i].needsDrumRerender {
            renderDrums(i)
        }
    }

    // MARK: Derived

    var duration: Double { project.durationSeconds }
    var visibleTrackCount: Int { project.visibleTrackCount }
    /// Track indices on screen, top to bottom.
    var visibleLanes: [Int] { project.visibleLanes }

    /// Press-and-hold reordering of lanes. Not while recording.
    func moveLanes(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !isRecording else { return }
        checkpoint("Reorder Tracks")
        project.moveLanes(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }
    var developerMode: Bool { settings.developerMode }
    var hasAnyAudio: Bool { project.tracks.contains { !$0.isEmpty } }

    // MARK: Lifecycle

    func close() {
        guard !isClosed else { return }
        stopClickPreview()
        if isRecording { stopRecording() }
        if isPlaying { pause() }
        cleanupJobs.values.forEach { $0.cancel() }
        project.playheadSeconds = playhead
        saveNow()
        ticker?.cancel()
        engine.teardown()
        AudioSessionManager.shared.onEvent = nil
        history.clear()
        isClosed = true
    }

    func enteredBackground() {
        stopClickPreview()
        project.playheadSeconds = playhead
        saveNow()
    }

    // MARK: Transport

    /// Re-anchors the waveform clock to the engine after any transport change.
    private func syncClock() {
        if isPlaying || isRecording {
            let anchor = engine.timelineAnchor
            let nowHost = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            clock = PlayheadClock(seconds: anchor.seconds, date: Date().addingTimeInterval(anchor.hostSeconds - nowHost), running: true)
        } else {
            clock = PlayheadClock(seconds: playhead, date: Date(), running: false)
        }
    }

    func togglePlay() {
        if isRecording {
            stopRecording()
            return
        }
        isPlaying ? pause() : play()
    }

    func play() {
        guard !isRecording, !isSaving else { return }
        stopClickPreview()
        // Voice Memos behavior: at the end, play from the start.
        if playhead >= duration - 0.01 { playhead = 0 }
        guard duration > 0 else { return }
        do {
            try engine.play(from: playhead, metronome: metronomeIfEnabled)
            isPlaying = true
            syncClock()
            startTicker()
        } catch {
            errorMessage = "Playback couldn't start. \(error.localizedDescription)"
        }
    }

    func pause() {
        guard isPlaying else { return }
        playhead = min(engine.pause(), duration)
        isPlaying = false
        syncClock()
        project.playheadSeconds = playhead
        scheduleSave()
    }

    func skip(by seconds: Double) {
        seek(to: playhead + seconds)
    }

    func returnToStart() {
        seek(to: 0)
    }

    func seek(to seconds: Double) {
        guard !isRecording else { return }
        let target = min(max(0, seconds), duration)
        let wasPlaying = isPlaying
        if wasPlaying { _ = engine.pause() }
        playhead = target
        engine.seek(to: target)
        project.playheadSeconds = target
        if wasPlaying {
            try? engine.play(from: target, metronome: metronomeIfEnabled)
        }
        syncClock()
        scheduleSave()
    }

    // Scrubbing: dragging the waveform moves the playhead like Voice Memos.

    func beginScrub() {
        guard !isRecording else { return }
        scrubWasPlaying = isPlaying
        if isPlaying {
            playhead = engine.pause()
            isPlaying = false
        }
        syncClock()
    }

    func scrub(to seconds: Double) {
        guard !isRecording else { return }
        playhead = min(max(0, seconds), duration)
        engine.seek(to: playhead)
        syncClock()
    }

    func endScrub() {
        guard !isRecording else { return }
        project.playheadSeconds = playhead
        scheduleSave()
        if scrubWasPlaying {
            scrubWasPlaying = false
            play()
        }
    }

    // MARK: Recording

    func toggleRecord() {
        if isRecording {
            stopRecording()
        } else {
            Task { await startRecording() }
        }
    }

    func startRecording(skipHeadphoneTip: Bool = false) async {
        guard !isRecording, !isSaving, !isStartingRecording else { return }
        // First time recording audio with an audible click and no headphones:
        // the mic would pick the click up. Suggest headphones once, before recording.
        if !skipHeadphoneTip, needsMetronomeHeadphoneTip {
            settings.metronomeHeadphoneTipShown = true
            showMetronomeHeadphoneTip = true
            return
        }
        isStartingRecording = true
        defer { isStartingRecording = false }
        stopClickPreview()
        // Pressing record while the song plays punches in from the live spot.
        let punch = isPlaying
        if project.tracks[armedTrack].isDrums {
            startDrumTake(punch: punch)
            return
        }
        guard await AudioSessionManager.shared.requestPermission() else {
            if punch { pause() }
            showPermissionDenied = true
            return
        }
        do {
            try engine.startIfNeeded()
        } catch {
            errorMessage = "The microphone couldn't start. \(error.localizedDescription)"
            return
        }
        let route = AudioSessionManager.shared.currentRoute
        if route == .bluetooth && !settings.latency.bluetoothTipShown {
            settings.latency.bluetoothTipShown = true
            showBluetoothTip = true
        }
        let echoCancellation = wantsEchoCancellation(route)
        let trackIndex = armedTrack
        let scratch = store.recordingTempURL(project: project.id)

        if punch, let plan = try? engine.punchInRecording(
            trackIndex: trackIndex,
            scratchURL: scratch,
            latency: latencyCompensation(route),
            route: route,
            inputGainDB: project.tracks[trackIndex].inputGainDB,
            echoCancellation: echoCancellation
        ) {
            // Seamless: the song never stops.
            let marker = PendingRecording(
                trackIndex: trackIndex,
                insertFrame: plan.startFrame,
                skipFrames: Int64((plan.latency * EngineFormat.sampleRate).rounded()),
                inputGainDB: plan.inputGainDB,
                route: route
            )
            try? store.savePendingRecording(marker, project: project.id)
            pendingMarkerFinal = false
            playhead = Double(plan.startFrame) / EngineFormat.sampleRate
            recordingStartSeconds = playhead
            livePeaks = []
            isPlaying = false
            isRecording = true
            isCountingIn = false
            syncClock()
            startTicker()
            return
        }
        // Couldn't punch in seamlessly (first recording sets up the mic, or echo
        // cancellation has to switch): stop and record from right here instead,
        // with no count-in.
        if punch { pause() }
        // Set up the microphone (and echo cancellation) first, so the latency
        // estimate reflects the path this take really uses.
        do {
            try engine.prepareInput(echoCancellation: echoCancellation)
        } catch {
            errorMessage = "The microphone couldn't start. \(error.localizedDescription)"
            return
        }
        let latency = latencyCompensation(route)

        // A new track starts at 0:00 when recording from a stop; overwrite-anywhere
        // applies once it has a take, and a punch-in records from the live spot.
        if project.tracks[trackIndex].isEmpty && !punch {
            playhead = 0
            engine.seek(to: 0)
        }
        let startFrame = Int64((playhead * EngineFormat.sampleRate).rounded())

        // Crash-safety marker; refined with exact timing once audio arrives.
        let marker = PendingRecording(
            trackIndex: trackIndex,
            insertFrame: startFrame,
            skipFrames: Int64((latency * EngineFormat.sampleRate).rounded()),
            inputGainDB: project.tracks[trackIndex].inputGainDB,
            route: route
        )
        try? store.savePendingRecording(marker, project: project.id)
        pendingMarkerFinal = false

        do {
            _ = try engine.startRecording(
                trackIndex: trackIndex,
                from: playhead,
                project: project,
                scratchURL: scratch,
                latency: latency,
                route: route,
                echoCancellation: echoCancellation,
                metronome: punch ? metronomeWithoutCountIn : metronomeIfEnabled
            )
        } catch {
            store.clearPendingRecording(project: project.id)
            errorMessage = "Recording couldn't start. \(error.localizedDescription)"
            return
        }
        recordingStartSeconds = playhead
        livePeaks = []
        isRecording = true
        isCountingIn = punch ? false : (metronomeIfEnabled.map { $0.countInBars > 0 } ?? false)
        syncClock()
        startTicker()
    }

    /// Recording through the iPhone speaker: Apple's echo cancellation keeps the
    /// playing tracks and the click out of the take, like Voice Memos layering.
    /// Headphones don't need it, so their tone stays untouched.
    private func wantsEchoCancellation(_ route: AudioRouteKind) -> Bool {
        settings.speakerEchoCancellation && route == .speaker
    }

    /// How far to move a take earlier. Echo cancellation adds its own delay,
    /// so a calibration measured without it doesn't apply; use the engine's
    /// estimate of the processed path instead.
    private func latencyCompensation(_ route: AudioRouteKind) -> Double {
        if engine.voiceProcessingActive {
            return max(0, engine.estimatedLatency + (settings.latency.manualOffsetMs[route] ?? 0) / 1000)
        }
        return settings.latency.compensation(for: route, estimate: engine.estimatedLatency)
    }

    private var needsMetronomeHeadphoneTip: Bool {
        !settings.metronomeHeadphoneTipShown
            && !wantsEchoCancellation(AudioSessionManager.shared.currentRoute)
            && !project.tracks[armedTrack].isDrums
            && !isSimple
            && project.metronome.mode == .on
            && AudioSessionManager.shared.currentRoute == .speaker
    }

    /// The click without a count-in, for recording that starts mid-song.
    private var metronomeWithoutCountIn: MetronomeSettings? {
        guard var s = metronomeIfEnabled else { return nil }
        s.countInBars = 0
        return s
    }

    func stopRecording() {
        if isDrumTake {
            stopDrumTake()
            return
        }
        guard isRecording, let result = engine.stopRecording() else { return }
        isRecording = false
        isCountingIn = false
        let stopSeconds = max(result.stopSeconds, recordingStartSeconds)
        finalize(sink: result.sink, plan: result.plan)
        playhead = stopSeconds
        engine.seek(to: playhead)
        syncClock()
    }

    /// Splices the scratch recording into its track off the main thread.
    private func finalize(sink: RecordingSink, plan: RecordingPlan) {
        let placement = plan.placement(firstSampleHost: sink.firstSampleHostTime)
        let pending = PendingRecording(trackIndex: plan.trackIndex, insertFrame: placement.insert, skipFrames: placement.skip, inputGainDB: plan.inputGainDB, route: plan.route)
        try? store.savePendingRecording(pending, project: project.id)
        splice(pending: pending, scratchURL: sink.url)
    }

    private func splice(pending: PendingRecording, scratchURL: URL) {
        let index = pending.trackIndex
        checkpoint("Recording", audio: true)
        let destination = store.audioURL(project: project.id, track: index)
        let existing = project.tracks[index].audioFileName.map { store.fileURL($0, in: project.id) }
        let peaksURL = store.peaksURL(project: project.id, track: index)
        isSaving = true
        livePeaks = []
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<[Float], Error> in
                do {
                    try Splicer.splice(.init(
                        trackURL: existing,
                        destinationURL: destination,
                        recordingURL: scratchURL,
                        recordingSkipFrames: pending.skipFrames,
                        insertFrame: pending.insertFrame,
                        inputGainDB: pending.inputGainDB
                    ))
                    let peaks = try PeakGenerator.peaks(ofFileAt: destination)
                    try? PeakGenerator.write(peaks, to: peaksURL)
                    return .success(peaks)
                } catch {
                    return .failure(error)
                }
            }.value
            self.didSplice(index: index, route: pending.route, outcome: outcome)
        }
    }

    private func didSplice(index: Int, route: AudioRouteKind, outcome: Result<[Float], Error>) {
        isSaving = false
        switch outcome {
        case .success(let newPeaks):
            store.clearPendingRecording(project: project.id)
            var track = project.tracks[index]
            if newPeaks.isEmpty && track.isEmpty {
                // Stopped during the count-in: nothing was recorded.
                try? FileManager.default.removeItem(at: store.audioURL(project: project.id, track: index))
                try? FileManager.default.removeItem(at: store.peaksURL(project: project.id, track: index))
                return
            }
            track.audioFileName = ProjectStore.audioFileName(track: index)
            track.lastRecordedRoute = route
            // The old Cleanup render no longer matches the take.
            if let cleaned = track.cleanedFileName {
                try? FileManager.default.removeItem(at: store.fileURL(cleaned, in: project.id))
                track.cleanedFileName = nil
            }
            project.tracks[index] = track
            peaks[index] = newPeaks
            takeGeneration[index] += 1
            cleanupJobs[index]?.cancel()
            store.refreshDurations(&project)
            project.updatedAt = Date()
            saveNow()
            engine.load(project: project, store: store)
            applyAll()
            // Clean Up re-renders a new take if it's on. No "Clean up this take?" prompt:
            // the Clean Up pill is right there on the track.
            if track.cleanup > 0 {
                runCleanup(index)
            }
        case .failure(let error):
            // The scratch file and marker stay on disk; recovery retries on next open.
            errorMessage = "The take couldn't be saved. It will be recovered next time you open this project. (\(error.localizedDescription))"
        }
    }

    /// A take captured before a crash or kill is spliced in on next open.
    private func recoverPendingRecording() {
        guard let pending = store.pendingRecording(project: project.id),
              project.tracks.indices.contains(pending.trackIndex) else {
            store.clearPendingRecording(project: project.id)
            return
        }
        splice(pending: pending, scratchURL: store.recordingTempURL(project: project.id))
    }

    // MARK: Ticker (playhead, live waveform, meters)

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                if !self.isPlaying && !self.isRecording && !self.settings.developerMode { return }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func tick() {
        if isRecording {
            playhead = engine.currentSeconds
            isCountingIn = !engine.isPastCountIn
            if isDrumTake {
                // Extend the live region up to "now" so the lane scrolls with the take.
                let wanted = Int((playhead - drumTakeStart) * WaveformView.peaksPerSecond)
                if wanted > livePeaks.count { livePeaks += [Float](repeating: 0, count: wanted - livePeaks.count) }
            } else if let sink = engine.recordingSink, let plan = engine.recordingPlan {
                if isCountingIn {
                    livePeaks = []
                } else {
                    // Drop pre-roll and latency so the live waveform sits where the take will land.
                    let skip = plan.placement(firstSampleHost: sink.firstSampleHostTime).skip
                    let skipPeaks = Int(skip / Int64(PeakGenerator.framesPerPeak))
                    let all = sink.livePeaks()
                    livePeaks = skipPeaks < all.count ? Array(all[skipPeaks...]) : []
                }
                refinePendingMarker(sink: sink)
            }
        } else if isPlaying {
            let position = engine.currentSeconds
            if position >= duration {
                playhead = duration
                pause()
            } else {
                playhead = position
            }
        }
        updateMeters()
    }

    private func refinePendingMarker(sink: RecordingSink) {
        guard !pendingMarkerFinal, let first = sink.firstSampleHostTime, let plan = engine.recordingPlan else { return }
        let placement = plan.placement(firstSampleHost: first)
        let marker = PendingRecording(trackIndex: plan.trackIndex, insertFrame: placement.insert, skipFrames: placement.skip, inputGainDB: plan.inputGainDB, route: plan.route)
        try? store.savePendingRecording(marker, project: project.id)
        pendingMarkerFinal = true
    }

    private func updateMeters() {
        guard settings.developerMode else { return }
        meterLevels = engine.meters.snapshot()
    }

    func developerModeChanged() {
        engine.setMetersEnabled(settings.developerMode)
        if !settings.speakerEchoCancellation { engine.disableVoiceProcessingIfIdle() }
        applyAll()
        if settings.developerMode { startTicker() }
    }

    func resetClip(_ index: Int) {
        engine.meters.resetClip(index: index)
        updateMeters()
    }

    // MARK: Session events

    private func handleSessionEvent(_ event: AudioSessionManager.Event) {
        switch event {
        case .interruptionBegan:
            // Calls, Siri, alarms: keep everything captured so far.
            if isRecording { stopRecording() }
            if isPlaying { pause() }
        case .interruptionEnded:
            try? engine.startIfNeeded()
        case .outputDeviceLost:
            if isRecording { stopRecording() }
            if isPlaying { pause() }
            if !wantsEchoCancellation(AudioSessionManager.shared.currentRoute) { engine.disableVoiceProcessingIfIdle() }
        case .routeChanged:
            // Headphones in: playback no longer needs echo cancellation.
            if !isPlaying && !isRecording && !wantsEchoCancellation(AudioSessionManager.shared.currentRoute) {
                engine.disableVoiceProcessingIfIdle()
            }
        case .mediaServicesReset:
            if isRecording { stopRecording() }
            isPlaying = false
            engine.rebuild()
            engine.load(project: project, store: store)
            applyAll()
            engine.setMetersEnabled(settings.developerMode)
        }
    }

    private func handleEngineWillReconfigure() {
        if isRecording { stopRecording() }
        if isPlaying {
            playhead = min(engine.pause(), duration)
            isPlaying = false
        }
        syncClock()
    }

    // MARK: Tracks

    /// For the in-app tests only.
    var engineForTesting: MixerEngine { engine }

    func arm(_ index: Int) {
        guard !isRecording, project.visibleLanes.contains(index) else { return }
        armedTrack = index
        routePadsIfNeeded()
    }

    // MARK: Drums

    /// An empty track can switch between audio and drums.
    func setKind(_ index: Int, _ kind: TrackKind) {
        guard !isRecording, project.tracks[index].isEmpty, project.tracks[index].kind != kind else { return }
        guard !(isSimple && kind == .drums) else { return }
        checkpoint("Track Type")
        project.tracks[index].kind = kind
        if kind == .drums && project.tracks[index].name == "Track \(index + 1)" {
            project.tracks[index].name = "Drums"
        } else if kind == .audio && project.tracks[index].name == "Drums" {
            project.tracks[index].name = "Track \(index + 1)"
        }
        routePadsIfNeeded()
        scheduleSave()
    }

    var isDrumArmed: Bool { project.tracks[armedTrack].isDrums }

    /// Points the live pads at the armed drum track's chain and kit.
    private func routePadsIfNeeded() {
        let track = project.tracks[armedTrack]
        guard track.isDrums else { return }
        engine.routePads(to: armedTrack, kit: track.drumKit, pads: track.padSettings)
    }

    /// Plays a pad; during a drum take, also records the hit.
    func hitPad(_ pad: Int) {
        let velocity: Float = 0.9
        do {
            try engine.hitPad(pad, velocity: velocity)
        } catch {
            errorMessage = "Audio couldn't start. \(error.localizedDescription)"
            return
        }
        guard isDrumTake, engine.isPastCountIn else { return }
        let time = max(drumTakeStart, engine.currentSeconds - engine.padTimingCompensation)
        drumTakeHits.append(DrumHit(time: time, pad: pad, velocity: velocity))
        drawLiveHit(pad: pad, at: time)
    }

    /// Changes a drum track's kit and re-renders its existing hits with it.
    func setDrumKit(_ index: Int, _ kit: DrumKit) {
        guard project.tracks[index].isDrums, project.tracks[index].drumKit != kit else { return }
        checkpoint("Drum Kit", audio: true)
        project.tracks[index].drumKit = kit
        if index == armedTrack { routePadsIfNeeded() }
        scheduleSave()
        if !project.tracks[index].drumHits.isEmpty {
            renderDrums(index)
        }
    }

    private func startDrumTake(punch: Bool = false) {
        let index = armedTrack
        stopClickPreview()
        if punch, let start = engine.punchInDrums(trackIndex: index) {
            // Seamless drum punch-in: hits record from the live spot.
            routePadsIfNeeded()
            playhead = start
            drumTakeStart = start
            drumTakeHits = []
            recordingStartSeconds = start
            livePeaks = []
            isPlaying = false
            isDrumTake = true
            isRecording = true
            isCountingIn = false
            syncClock()
            startTicker()
            return
        }
        if isPlaying { pause() }
        // Drum takes start wherever the playhead is, even on an empty track
        // (the rendered track is silent before the first hit).
        routePadsIfNeeded()
        do {
            try engine.startDrumTake(trackIndex: index, from: playhead, project: project, metronome: metronomeIfEnabled)
        } catch {
            errorMessage = "Recording couldn't start. \(error.localizedDescription)"
            return
        }
        drumTakeStart = playhead
        drumTakeHits = []
        recordingStartSeconds = playhead
        livePeaks = []
        isDrumTake = true
        isRecording = true
        isCountingIn = metronomeIfEnabled.map { $0.countInBars > 0 } ?? false
        syncClock()
        startTicker()
    }

    private func stopDrumTake() {
        let stopSeconds = max(engine.stopDrumTake(), drumTakeStart)
        isDrumTake = false
        isRecording = false
        isCountingIn = false
        let index = armedTrack
        checkpoint("Drum Recording", audio: true)
        project.tracks[index].drumHits = DrumRenderer.overwrite(project.tracks[index].drumHits, from: drumTakeStart, to: stopSeconds, with: drumTakeHits)
        drumTakeHits = []
        playhead = stopSeconds
        engine.seek(to: playhead)
        syncClock()
        renderDrums(index)
    }

    /// Adds a hit's waveform to the live peaks while a take is running.
    private func drawLiveHit(pad: Int, at time: Double) {
        let kit = project.tracks[armedTrack].drumKit
        if padPeaksCache[kit] == nil {
            padPeaksCache[kit] = (0..<DrumKit.padCount).map { PeakGenerator.peaks(of: kit.sample(pad: $0)) }
        }
        guard let hitPeaks = padPeaksCache[kit]?[pad] else { return }
        let start = Int((time - drumTakeStart) * WaveformView.peaksPerSecond)
        guard start >= 0 else { return }
        let needed = start + hitPeaks.count
        if livePeaks.count < needed { livePeaks += [Float](repeating: 0, count: needed - livePeaks.count) }
        for (i, p) in hitPeaks.enumerated() where p > livePeaks[start + i] {
            livePeaks[start + i] = p
        }
    }

    /// Renders a drum track's hits with its kit into its audio file, off the main thread.
    private func renderDrums(_ index: Int) {
        let track = project.tracks[index]
        let hits = track.playableDrumHits
        let kit = track.drumKit
        let pads = track.padSettings
        let url = store.audioURL(project: project.id, track: index)
        let peaksURL = store.peaksURL(project: project.id, track: index)
        drumRenderGeneration[index] += 1
        let generation = drumRenderGeneration[index]
        isSaving = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<[Float], Error> in
                do {
                    if hits.isEmpty {
                        try? FileManager.default.removeItem(at: url)
                        try? FileManager.default.removeItem(at: peaksURL)
                        return .success([])
                    }
                    try DrumRenderer.write(hits, kit: kit, pads: pads, to: url)
                    let peaks = try PeakGenerator.peaks(ofFileAt: url)
                    try? PeakGenerator.write(peaks, to: peaksURL)
                    return .success(peaks)
                } catch {
                    return .failure(error)
                }
            }.value
            guard generation == self.drumRenderGeneration[index] else { return }
            self.isSaving = false
            self.livePeaks = []
            switch outcome {
            case .success(let newPeaks):
                self.project.tracks[index].audioFileName = hits.isEmpty ? nil : ProjectStore.audioFileName(track: index)
                self.project.tracks[index].drumRenderVersion = DrumRenderer.version
                self.peaks[index] = newPeaks
                self.store.refreshDurations(&self.project)
                self.saveNow()
                let wasPlaying = self.isPlaying
                if wasPlaying { self.playhead = self.engine.pause() }
                self.engine.load(project: self.project, store: self.store)
                self.applyAll()
                if wasPlaying { try? self.engine.play(from: self.playhead, metronome: self.metronomeIfEnabled) }
                self.syncClock()
            case .failure(let error):
                self.errorMessage = "The drum track couldn't be saved. \(error.localizedDescription)"
            }
        }
    }

    /// Reveals the next lane, arms it and rewinds, so the new part is laid
    /// down from the top of the song.
    func addTrack(kind requested: TrackKind = .audio) {
        guard !isRecording, project.visibleTrackCount < Project.trackCount else { return }
        // Simple projects only have audio tracks.
        let kind: TrackKind = isSimple ? .audio : requested
        checkpoint("Add Track")
        project.visibleTrackCount += 1
        armedTrack = project.laneOrder[project.visibleTrackCount - 1]
        if project.tracks[armedTrack].isEmpty {
            project.tracks[armedTrack].kind = kind
            if kind == .drums && project.tracks[armedTrack].name == "Track \(armedTrack + 1)" {
                project.tracks[armedTrack].name = "Drums"
            }
        }
        routePadsIfNeeded()
        // While the song plays, a new track appears without stopping or
        // jumping; from a stop, it rewinds so the part is laid down from the top.
        if !isPlaying { seek(to: 0) }
        scheduleSave()
    }

    // MARK: Pad settings

    /// While the pad bubble is open: hear a draft on the live pads without saving it.
    func previewPadSettings(track index: Int, pad: Int, _ settings: PadSettings) {
        guard index == armedTrack, project.tracks[index].isDrums, project.tracks[index].padSettings.indices.contains(pad) else { return }
        var pads = project.tracks[index].padSettings
        pads[pad] = settings
        engine.routePads(to: index, kit: project.tracks[index].drumKit, pads: pads)
    }

    /// The bubble closed without Apply: back to the saved sound.
    func endPadPreview() {
        routePadsIfNeeded()
    }

    /// Apply: saves the pad's sound and re-renders the track's existing hits with it.
    func applyPadSettings(track index: Int, pad: Int, _ settings: PadSettings) {
        guard !isRecording, project.tracks[index].isDrums, project.tracks[index].padSettings.indices.contains(pad),
              project.tracks[index].padSettings[pad] != settings else {
            routePadsIfNeeded()
            return
        }
        checkpoint("\(project.tracks[index].drumKit.padNames[pad]) Sound", audio: true)
        project.tracks[index].padSettings[pad] = settings
        routePadsIfNeeded()
        scheduleSave()
        if !project.tracks[index].drumHits.isEmpty { renderDrums(index) }
    }

    func revertPad(track index: Int, pad: Int) {
        applyPadSettings(track: index, pad: pad, .default)
    }

    // MARK: Quantize

    /// Q: snaps the drum track to the grid at the current tempo, or back to as played.
    func toggleQuantize(_ index: Int) {
        guard !isRecording, project.tracks[index].isDrums else { return }
        var q = project.tracks[index].quantize
        if q.enabled {
            q.enabled = false
        } else {
            q = QuantizeSettings(enabled: true, division: q.division, bpm: project.metronome.bpm, beatUnit: project.metronome.beatUnit)
        }
        setQuantize(index, q, label: q.enabled ? "Quantize" : "Quantize Off")
    }

    /// Picks the grid (press and hold Q); turns quantize on at the current tempo.
    func setQuantizeDivision(_ index: Int, _ division: QuantizeDivision) {
        guard !isRecording, project.tracks[index].isDrums else { return }
        let q = QuantizeSettings(enabled: true, division: division, bpm: project.metronome.bpm, beatUnit: project.metronome.beatUnit)
        setQuantize(index, q, label: "Quantize \(division.label)")
    }

    private func setQuantize(_ index: Int, _ q: QuantizeSettings, label: String) {
        guard project.tracks[index].quantize != q else { return }
        checkpoint(label, audio: true)
        project.tracks[index].quantize = q
        scheduleSave()
        if !project.tracks[index].drumHits.isEmpty { renderDrums(index) }
    }

    // MARK: Simple / Full mode

    var isSimple: Bool { project.mode == .simple }

    /// Full mode adds the mixer, mute/solo, metronome, quantize and every drum kit.
    func switchToFullMode() {
        guard isSimple, !isRecording else { return }
        checkpoint("Full Mode")
        project.mode = .full
        scheduleSave()
    }

    /// Switching to Simple would turn off settings it hides (asks first).
    var simpleModeResetsSettings: Bool { project.usesFullModeFeatures }

    /// Simple mode has no drums: tracks with drum takes have to go first.
    var simpleModeBlockedByDrums: Bool { !project.drumTracksWithTakes.isEmpty }

    /// To Simple. Anything Simple mode hides is reset first so no hidden setting
    /// keeps changing the sound; it's one undo step.
    func switchToSimpleMode() {
        guard !isSimple, !isRecording, !isSaving, !simpleModeBlockedByDrums else { return }
        stopClickPreview()
        checkpoint("Simple Mode")
        mixMode = false
        if isPlaying { pause() }
        project.resetFullModeFeatures()
        project.mode = .simple
        // Arm an audio track (an empty drum track just became one).
        if !project.visibleLanes.contains(armedTrack) { armedTrack = project.visibleLanes.first ?? 0 }
        applyAll()
        scheduleSave()
    }

    // MARK: Undo / redo

    /// Records the project before a change. See `UndoHistory`.
    private func checkpoint(_ label: String, key: String? = nil, audio: Bool = false) {
        history.checkpoint(project, label: label, key: key, audio: audio)
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = history.canUndo
        canRedo = history.canRedo
        undoLabel = history.undoLabel
        redoLabel = history.redoLabel
    }

    /// Undo and redo wait for recording, saving and Cleanup renders to finish.
    var isUndoBlocked: Bool { isRecording || isSaving || isStartingRecording || !cleanupProgress.isEmpty }

    func undo() {
        guard !isUndoBlocked, let step = history.undo(current: project) else { return }
        restore(step.project)
    }

    func redo() {
        guard !isUndoBlocked, let step = history.redo(current: project) else { return }
        restore(step.project)
    }

    private func restore(_ snapshot: Project) {
        stopClickPreview()
        padRenderTask?.cancel()
        tempoRestartTask?.cancel()
        var restored = snapshot
        // Undo never pulls a binned project back out of Recently Deleted.
        restored.deletedAt = project.deletedAt
        project = restored
        refreshUndoState()
        afterTrackBinChange()
    }

    // MARK: Track bin

    /// Moves a track to the project's Recently Deleted (after the user confirms).
    func deleteTrack(_ index: Int) {
        guard !isRecording, !isSaving else { return }
        checkpoint("Delete Track", audio: true)
        cleanupJobs[index]?.cancel()
        takeGeneration[index] += 1
        drumRenderGeneration[index] += 1
        do {
            try store.binTrack(&project, index: index)
        } catch {
            errorMessage = "The track couldn't be deleted. \(error.localizedDescription)"
            return
        }
        afterTrackBinChange()
    }

    /// Puts a deleted track back into a free lane.
    func recoverTrack(_ id: UUID) {
        guard !isRecording, !isSaving else { return }
        if isSimple, project.deletedTracks.first(where: { $0.id == id })?.track.isDrums == true {
            errorMessage = "Drum tracks are only in Full mode. Switch to Full mode from the ⋯ menu to recover this one."
            return
        }
        guard project.freeSlotForRecovery() != nil else {
            errorMessage = "All four tracks are in use. Delete a track first, then recover this one."
            return
        }
        checkpoint("Recover Track", audio: true)
        do {
            let slot = try store.recoverTrack(&project, id: id)
            takeGeneration[slot] += 1
            drumRenderGeneration[slot] += 1
            afterTrackBinChange()
            armedTrack = slot
            routePadsIfNeeded()
        } catch ProjectStore.TrackBinError.noFreeLane {
            errorMessage = "All four tracks are in use. Delete a track first, then recover this one."
        } catch {
            errorMessage = "The track couldn't be recovered. \(error.localizedDescription)"
        }
    }

    func deleteTrackPermanently(_ id: UUID) {
        checkpoint("Delete Track Permanently", audio: true)
        store.deleteTrackPermanently(&project, id: id)
        saveNow()
    }

    private func afterTrackBinChange() {
        let wasPlaying = isPlaying
        if wasPlaying { playhead = engine.pause() }
        saveNow()
        engine.load(project: project, store: store)
        applyAll()
        loadPeaks()
        if !project.visibleLanes.contains(armedTrack) {
            armedTrack = project.visibleLanes.first(where: { project.tracks[$0].isEmpty }) ?? project.visibleLanes.last ?? 0
        }
        routePadsIfNeeded()
        playhead = min(playhead, project.durationSeconds)
        if wasPlaying {
            try? engine.play(from: playhead, metronome: metronomeIfEnabled)
        } else {
            engine.seek(to: playhead)
        }
        syncClock()
    }

    func rename(track index: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = trimmed.isEmpty ? "Track \(index + 1)" : trimmed
        guard newName != project.tracks[index].name else { return }
        checkpoint("Rename Track")
        project.tracks[index].name = newName
        scheduleSave()
    }

    func renameProject(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != project.name else { return }
        checkpoint("Rename Project")
        project.name = trimmed
        scheduleSave()
    }

    func toggleMute(_ index: Int) {
        checkpoint("Mute")
        project.tracks[index].mute.toggle()
        applyAll()
        scheduleSave()
    }

    func toggleSolo(_ index: Int) {
        checkpoint("Solo")
        project.tracks[index].solo.toggle()
        applyAll()
        scheduleSave()
    }

    /// Generic slider edit. Moving a macro hands control back from any
    /// Developer Mode override of the same section.
    func update(track index: Int, label: String = "Mix Change", key: String? = nil, _ change: (inout Track) -> Void) {
        checkpoint(label, key: key ?? "\(label)-\(index)")
        change(&project.tracks[index])
        engine.chains[index].apply(project.tracks[index], audible: project.isAudible(index), warmthEnabled: warmthActive)
        scheduleSave()
    }

    func setVolume(_ index: Int, _ value: Double) { update(track: index, label: "Volume") { $0.volume = value } }

    func setEQ(_ index: Int, low: Double? = nil, mid: Double? = nil, high: Double? = nil) {
        update(track: index, label: low != nil ? "Low" : (mid != nil ? "Mid" : "High")) { t in
            if let low { t.eqLow = low }
            if let mid { t.eqMid = mid }
            if let high { t.eqHigh = high }
            t.devOverrides?.eq = nil
            t.devOverrides = t.devOverrides.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    func setCompressor(_ index: Int, _ value: Double) {
        update(track: index, label: "Compressor") { t in
            t.compressor = value
            t.devOverrides?.compressor = nil
            t.devOverrides = t.devOverrides.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    func setSpace(_ index: Int, _ value: Double) {
        update(track: index, label: "Space") { t in
            t.space = value
            t.devOverrides?.reverb = nil
            t.devOverrides = t.devOverrides.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    func setWarmth(_ index: Int, _ value: Double) { update(track: index, label: "Warmth") { $0.warmth = value } }

    /// The on/off button under M/S. Off remembers the level for next time.
    func toggleCleanup(_ index: Int) {
        let track = project.tracks[index]
        guard !track.isDrums else { return }
        if track.isCleanupOn {
            update(track: index, label: "Clean Up Off", key: UUID().uuidString) { t in
                t.cleanupLevel = t.cleanup
                t.cleanup = 0
            }
        } else {
            setCleanup(index, track.cleanupLevel > 0 ? track.cleanupLevel : Track.defaultCleanupLevel)
        }
    }

    /// Moving Cleanup above zero renders the cleaned copy if it doesn't exist yet.
    func setCleanup(_ index: Int, _ value: Double) {
        update(track: index, label: "Clean Up") { t in
            t.cleanup = value
            if value > 0 { t.cleanupLevel = value }
        }
        if value > 0, project.tracks[index].cleanedFileName == nil, !project.tracks[index].isEmpty, cleanupProgress[index] == nil {
            runCleanup(index)
        }
    }

    func setMasterVolume(_ value: Double) {
        checkpoint("Master Volume", key: "master")
        project.masterVolume = value
        engine.master.apply(masterVolume: value)
        scheduleSave()
    }

    // Developer Mode exploded values

    func editDevParams(_ index: Int, _ change: (inout DevParams, Track) -> Void) {
        update(track: index, label: "Advanced Control") { t in
            var params = t.devOverrides ?? DevParams()
            change(&params, t)
            t.devOverrides = params.isEmpty ? nil : params
        }
    }

    func resetDevOverrides(_ index: Int) {
        update(track: index, label: "Reset to Macros", key: UUID().uuidString) { $0.devOverrides = nil }
    }

    func setMetronome(_ change: (inout MetronomeSettings) -> Void) {
        let before = project.metronome
        var proposed = before
        change(&proposed)
        guard proposed != before else { return }
        checkpoint("Metronome", key: "metronome")
        project.metronome = proposed
        let after = project.metronome
        scheduleSave()
        if isPreviewingClick {
            // Turning the metronome off ends the preview; anything else applies live.
            if after.mode == .off && before.mode != .off {
                stopClickPreview()
            } else {
                engine.metronome.update(settings: previewSettings)
            }
            return
        }
        // While playing or recording, nothing restarts: changes apply live.
        guard isPlaying || isRecording else { return }
        if before.enabled && after.enabled, let live = metronomeIfEnabled {
            // Tempo, time signature, volume, Click <-> Silent: the beat carries on
            // from where it is, just faster or slower.
            engine.metronome.update(settings: live)
        } else if let live = metronomeIfEnabled {
            // Switched on after pressing play or record: joins in on the beat.
            engine.startClickLive(settings: live)
        } else {
            engine.stopClick()
        }
    }

    /// Beat lines for the waveforms while the metronome is on (Click or Silent).
    var beatGrid: BeatGrid? {
        guard !isSimple, project.metronome.enabled else { return nil }
        let m = project.metronome
        // While the click runs, follow its (possibly moved) grid; otherwise the
        // grid the next play will start on.
        let a = (isPlaying || isRecording) ? beatAnchor : (seconds: 0, beat: 0)
        return BeatGrid(bpm: m.bpm, beatsPerBar: m.beatsPerBar, anchorSeconds: a.seconds, anchorBeat: a.beat)
    }

    /// Where the click's beat grid is anchored (moves when the tempo changes
    /// while it plays), for the beat lights.
    var beatAnchor: (seconds: Double, beat: Double) {
        (Double(engine.metronome.anchorFrame) / EngineFormat.sampleRate, engine.metronome.anchorBeat)
    }

    // MARK: Click preview

    /// The metronome's own play button: the click alone, to try a tempo before
    /// playing or recording. Silent mode previews the beat lights only.
    func toggleClickPreview() {
        if isPreviewingClick { stopClickPreview() } else { startClickPreview() }
    }

    /// The preview clicks even if the metronome is Off; Silent stays silent.
    private var previewSettings: MetronomeSettings {
        var s = project.metronome
        if s.mode == .off { s.mode = .on }
        if s.mode == .visual { s.volume = 0 }
        return s
    }

    private func startClickPreview() {
        guard !isPlaying, !isRecording, !isSaving else { return }
        do {
            let firstClickHost = try engine.startClickPreview(settings: previewSettings)
            let nowHost = AVAudioTime.seconds(forHostTime: mach_absolute_time())
            previewClock = PlayheadClock(seconds: 0, date: Date().addingTimeInterval(firstClickHost - nowHost), running: true)
            isPreviewingClick = true
        } catch {
            errorMessage = "Audio couldn't start. \(error.localizedDescription)"
        }
    }

    func stopClickPreview() {
        guard isPreviewingClick else { return }
        engine.stopClickPreview()
        isPreviewingClick = false
        previewClock = PlayheadClock(seconds: 0, date: Date(), running: false)
    }

    private func restartClickPreview() {
        engine.stopClickPreview()
        isPreviewingClick = false
        startClickPreview()
    }

    /// Tap the metronome: On → visual-only → Off.
    func cycleMetronomeMode() {
        setMetronome { $0.mode = $0.mode.next }
    }

    /// Tap the time signature: 4/4 → 3/4 → 2/4.
    func cycleTimeSignature() {
        setMetronome { $0.timeSignature = $0.timeSignature.nextQuick }
    }

    func setTimeSignature(_ signature: TimeSignature) {
        setMetronome { $0.timeSignature = signature }
    }

    /// Arrow taps move by the project's tempo step; holding moves by 1 BPM.
    func nudgeTempo(_ direction: Int, fine: Bool) {
        let delta = Double(direction) * (fine ? 1 : project.metronome.tempoStep)
        setMetronome { $0.nudgeTempo(by: delta) }
    }

    /// What the engine plays: nothing when off; a silent click when visual-only,
    /// so the count-in and beat grid behave exactly the same.
    private var metronomeIfEnabled: MetronomeSettings? {
        guard !isSimple, project.metronome.enabled else { return nil }
        var settings = project.metronome
        if settings.mode == .visual { settings.volume = 0 }
        return settings
    }

    private var warmthActive: Bool { settings.developerMode && settings.warmthEnabled }

    private func applyAll() {
        engine.apply(project: project, warmthEnabled: warmthActive)
        if !settings.developerMode {
            engine.master.apply(masterVolume: MacroCurves.volumeUnitySlider)
        }
    }

    // MARK: Cleanup

    func runCleanup(_ index: Int) {
        guard let name = project.tracks[index].audioFileName, cleanupProgress[index] == nil else { return }
        let input = store.fileURL(name, in: project.id)
        let output = store.cleanedURL(project: project.id, track: index)
        let projectID = project.id
        let generation = takeGeneration[index]
        cleanupProgress[index] = 0
        let job = ProgressBox()
        cleanupJobs[index] = job
        Task {
            let poll = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    self?.cleanupProgress[index] = job.value
                }
            }
            let outcome = await Task.detached(priority: .userInitiated) { () -> Error? in
                do {
                    try CleanupEngine.render(
                        input: input,
                        output: output,
                        progress: { job.value = $0 },
                        isCancelled: { job.isCancelled }
                    )
                    return nil
                } catch {
                    return error
                }
            }.value
            poll.cancel()
            self.didCleanup(index: index, projectID: projectID, generation: generation, error: outcome)
        }
    }

    private func didCleanup(index: Int, projectID: UUID, generation: Int, error: Error?) {
        cleanupProgress[index] = nil
        cleanupJobs[index] = nil
        guard !isClosed, projectID == project.id else { return }
        guard generation == takeGeneration[index] else {
            // The track was re-recorded while this render ran: render the new take instead.
            if error == nil {
                try? FileManager.default.removeItem(at: store.cleanedURL(project: project.id, track: index))
            }
            if project.tracks[index].cleanup > 0 && project.tracks[index].cleanedFileName == nil {
                runCleanup(index)
            }
            return
        }
        if let error {
            if !(error is CleanupPipeline.Failure) {
                errorMessage = "Cleanup failed. \(error.localizedDescription)"
            }
            return
        }
        project.tracks[index].cleanedFileName = ProjectStore.cleanedFileName(track: index)
        saveNow()
        let wasPlaying = isPlaying
        if wasPlaying { playhead = engine.pause() }
        engine.load(project: project, store: store)
        applyAll()
        if wasPlaying { try? engine.play(from: playhead, metronome: metronomeIfEnabled) }
        syncClock()
    }

    // MARK: Export

    enum ExportKind: Sendable {
        case mix
        case track(Int)
        case allTracks
    }

    func export(_ kind: ExportKind) {
        guard exportProgress == nil else { return }
        if isPlaying { pause() }
        let project = self.project
        let store = self.store
        let options = settings.exportOptions
        let warmth = warmthActive
        let progressBox = ProgressBox()
        exportProgress = 0
        Task {
            let poll = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    self?.exportProgress = progressBox.value
                }
            }
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[URL], Error> in
                do {
                    let report: @Sendable (Double) -> Void = { progressBox.value = $0 }
                    switch kind {
                    case .mix:
                        return .success([try Exporter.exportMix(project: project, store: store, options: options, warmthEnabled: warmth, progress: report)])
                    case .track(let i):
                        return .success([try Exporter.exportTrack(i, project: project, store: store, options: options, warmthEnabled: warmth, progress: report)])
                    case .allTracks:
                        return .success(try Exporter.exportAllTracks(project: project, store: store, options: options, warmthEnabled: warmth, progress: report))
                    }
                } catch {
                    return .failure(error)
                }
            }.value
            poll.cancel()
            self.exportProgress = nil
            switch result {
            case .success(let urls): self.exportedURLs = urls
            case .failure(let error): self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Latency calibration (Developer Mode)

    private(set) var isCalibrating = false

    func calibrateLatency() async -> String {
        guard !isRecording, !isCalibrating else { return "" }
        if isPlaying { pause() }
        guard await AudioSessionManager.shared.requestPermission() else {
            showPermissionDenied = true
            return "Microphone access is off."
        }
        isCalibrating = true
        defer { isCalibrating = false }
        let route = AudioSessionManager.shared.currentRoute
        let scratch = store.directory(for: project.id).appendingPathComponent(".calibration.caf")
        do {
            try engine.startIfNeeded()
            let seconds = try await LatencyCalibrator.run(engine: engine, scratchURL: scratch, route: route)
            settings.latency.measured[route] = seconds
            engine.seek(to: playhead)
            return String(format: "%@: %.1f ms", route.displayName, seconds * 1000)
        } catch {
            engine.seek(to: playhead)
            return error.localizedDescription
        }
    }

    var currentRoute: AudioRouteKind { AudioSessionManager.shared.currentRoute }
    var estimatedLatencyMs: Double { engine.estimatedLatency * 1000 }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        // A late save (e.g. a Cleanup render finishing) must not pull a binned project back out.
        if let onDisk = try? store.load(id: project.id), onDisk.deletedAt != nil {
            project.deletedAt = onDisk.deletedAt
        }
        project.updatedAt = Date()
        do {
            try store.save(project)
        } catch {
            errorMessage = "Couldn't save the project. \(error.localizedDescription)"
        }
    }

    private func loadPeaks() {
        for track in project.tracks {
            guard let name = track.audioFileName else {
                peaks[track.index] = []
                continue
            }
            let cache = store.peaksURL(project: project.id, track: track.index)
            if let cached = try? PeakGenerator.read(from: cache), !cached.isEmpty {
                peaks[track.index] = cached
            } else if let computed = try? PeakGenerator.peaks(ofFileAt: store.fileURL(name, in: project.id)) {
                peaks[track.index] = computed
                try? PeakGenerator.write(computed, to: cache)
            }
        }
    }
}

/// Progress and cancellation shared between a background job and the UI.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Double = 0
    private var _cancelled = false

    var value: Double {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }

    var isCancelled: Bool { lock.withLock { _cancelled } }

    func cancel() { lock.withLock { _cancelled = true } }
}
