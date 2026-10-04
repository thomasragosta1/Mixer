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
    private(set) var isPlaying = false
    private(set) var isRecording = false
    /// True during a count-in, before the take starts.
    private(set) var isCountingIn = false
    /// Splicing a finished take into its track.
    private(set) var isSaving = false
    var armedTrack = 0
    var mixMode = false

    /// Cleanup progress per track (nil = not running).
    private(set) var cleanupProgress: [Int: Double] = [:]
    /// Track to offer "Clean up this take?" for (speaker-route recordings).
    var cleanupOffer: Int?

    var showPermissionDenied = false
    var showBluetoothTip = false
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
    /// Bumped on every splice so a Cleanup render of an older take is discarded.
    @ObservationIgnored private var takeGeneration = [Int](repeating: 0, count: Project.trackCount)

    init(project: Project, store: ProjectStore, settings: AppSettings = .shared) {
        var project = project
        store.cleanTemporaryFiles(project: project.id)
        store.refreshDurations(&project)
        self.project = project
        self.store = store
        self.settings = settings
        self.engine = MixerEngine()
        playhead = min(project.playheadSeconds, project.durationSeconds)
        // Arm the first empty lane, or the last one if all have takes.
        armedTrack = project.visibleLanes.first(where: { project.tracks[$0].isEmpty }) ?? project.visibleLanes.last ?? 0
        engine.voiceProcessingEnabled = settings.voiceProcessing
        engine.load(project: project, store: store)
        applyAll()
        loadPeaks()
        engine.seek(to: playhead)
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
    }

    // MARK: Derived

    var duration: Double { project.durationSeconds }
    var visibleTrackCount: Int { project.visibleTrackCount }
    /// Track indices on screen, top to bottom.
    var visibleLanes: [Int] { project.visibleLanes }

    /// Press-and-hold reordering of lanes. Not while recording.
    func moveLanes(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !isRecording else { return }
        project.moveLanes(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }
    var developerMode: Bool { settings.developerMode }
    var hasAnyAudio: Bool { project.tracks.contains { !$0.isEmpty } }

    // MARK: Lifecycle

    func close() {
        guard !isClosed else { return }
        if isRecording { stopRecording() }
        if isPlaying { pause() }
        cleanupJobs.values.forEach { $0.cancel() }
        project.playheadSeconds = playhead
        saveNow()
        ticker?.cancel()
        engine.teardown()
        AudioSessionManager.shared.onEvent = nil
        isClosed = true
    }

    func enteredBackground() {
        project.playheadSeconds = playhead
        saveNow()
    }

    // MARK: Transport

    func togglePlay() {
        if isRecording {
            stopRecording()
            return
        }
        isPlaying ? pause() : play()
    }

    func play() {
        guard !isRecording, !isSaving else { return }
        // Voice Memos behavior: at the end, play from the start.
        if playhead >= duration - 0.01 { playhead = 0 }
        guard duration > 0 else { return }
        do {
            try engine.play(from: playhead, metronome: metronomeIfEnabled)
            isPlaying = true
            startTicker()
        } catch {
            errorMessage = "Playback couldn't start. \(error.localizedDescription)"
        }
    }

    func pause() {
        guard isPlaying else { return }
        playhead = min(engine.pause(), duration)
        isPlaying = false
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
    }

    func scrub(to seconds: Double) {
        guard !isRecording else { return }
        playhead = min(max(0, seconds), duration)
        engine.seek(to: playhead)
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

    func startRecording() async {
        guard !isRecording, !isSaving, !isStartingRecording else { return }
        isStartingRecording = true
        defer { isStartingRecording = false }
        if isPlaying { pause() }
        guard await AudioSessionManager.shared.requestPermission() else {
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
        let latency = settings.latency.compensation(for: route, estimate: engine.estimatedLatency)
        let trackIndex = armedTrack
        // A new track always starts at 0:00; overwrite-anywhere applies once it has a take.
        if project.tracks[trackIndex].isEmpty {
            playhead = 0
            engine.seek(to: 0)
        }
        let startFrame = Int64((playhead * EngineFormat.sampleRate).rounded())
        let scratch = store.recordingTempURL(project: project.id)

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
                metronome: metronomeIfEnabled
            )
        } catch {
            store.clearPendingRecording(project: project.id)
            errorMessage = "Recording couldn't start. \(error.localizedDescription)"
            return
        }
        recordingStartSeconds = playhead
        livePeaks = []
        isRecording = true
        isCountingIn = metronomeIfEnabled.map { $0.countInBars > 0 } ?? false
        startTicker()
    }

    func stopRecording() {
        guard isRecording, let result = engine.stopRecording() else { return }
        isRecording = false
        isCountingIn = false
        let stopSeconds = max(result.stopSeconds, recordingStartSeconds)
        finalize(sink: result.sink, plan: result.plan)
        playhead = stopSeconds
        engine.seek(to: playhead)
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
            if track.cleanup > 0 {
                runCleanup(index)
            } else if route == .speaker {
                cleanupOffer = index
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
            if let sink = engine.recordingSink, let plan = engine.recordingPlan {
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
        engine.setVoiceProcessing(settings.voiceProcessing)
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
        case .routeChanged:
            break
        case .mediaServicesReset:
            if isRecording { stopRecording() }
            isPlaying = false
            engine.rebuild()
            engine.voiceProcessingEnabled = settings.voiceProcessing
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
    }

    // MARK: Tracks

    func arm(_ index: Int) {
        guard !isRecording, project.visibleLanes.contains(index) else { return }
        armedTrack = index
    }

    /// Reveals the next lane, arms it and rewinds, so the new part is laid
    /// down from the top of the song.
    func addTrack() {
        guard !isRecording, project.visibleTrackCount < Project.trackCount else { return }
        project.visibleTrackCount += 1
        armedTrack = project.laneOrder[project.visibleTrackCount - 1]
        seek(to: 0)
        scheduleSave()
    }

    func rename(track index: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        project.tracks[index].name = trimmed.isEmpty ? "Track \(index + 1)" : trimmed
        scheduleSave()
    }

    func renameProject(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        project.name = trimmed
        scheduleSave()
    }

    func toggleMute(_ index: Int) {
        project.tracks[index].mute.toggle()
        applyAll()
        scheduleSave()
    }

    func toggleSolo(_ index: Int) {
        project.tracks[index].solo.toggle()
        applyAll()
        scheduleSave()
    }

    /// Generic slider edit. Moving a macro hands control back from any
    /// Developer Mode override of the same section.
    func update(track index: Int, _ change: (inout Track) -> Void) {
        change(&project.tracks[index])
        engine.chains[index].apply(project.tracks[index], audible: project.isAudible(index), warmthEnabled: warmthActive)
        scheduleSave()
    }

    func setVolume(_ index: Int, _ value: Double) { update(track: index) { $0.volume = value } }

    func setEQ(_ index: Int, low: Double? = nil, mid: Double? = nil, high: Double? = nil) {
        update(track: index) { t in
            if let low { t.eqLow = low }
            if let mid { t.eqMid = mid }
            if let high { t.eqHigh = high }
            t.devOverrides?.eq = nil
            t.devOverrides = t.devOverrides.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    func setCompressor(_ index: Int, _ value: Double) {
        update(track: index) { t in
            t.compressor = value
            t.devOverrides?.compressor = nil
            t.devOverrides = t.devOverrides.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    func setSpace(_ index: Int, _ value: Double) {
        update(track: index) { t in
            t.space = value
            t.devOverrides?.reverb = nil
            t.devOverrides = t.devOverrides.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    func setWarmth(_ index: Int, _ value: Double) { update(track: index) { $0.warmth = value } }

    /// The on/off button under M/S. Off remembers the level for next time.
    func toggleCleanup(_ index: Int) {
        let track = project.tracks[index]
        if track.isCleanupOn {
            update(track: index) { t in
                t.cleanupLevel = t.cleanup
                t.cleanup = 0
            }
        } else {
            setCleanup(index, track.cleanupLevel > 0 ? track.cleanupLevel : Track.defaultCleanupLevel)
        }
    }

    /// Moving Cleanup above zero renders the cleaned copy if it doesn't exist yet.
    func setCleanup(_ index: Int, _ value: Double) {
        update(track: index) { t in
            t.cleanup = value
            if value > 0 { t.cleanupLevel = value }
        }
        if value > 0, project.tracks[index].cleanedFileName == nil, !project.tracks[index].isEmpty, cleanupProgress[index] == nil {
            runCleanup(index)
        }
    }

    func setMasterVolume(_ value: Double) {
        project.masterVolume = value
        engine.master.apply(masterVolume: value)
        scheduleSave()
    }

    // Developer Mode exploded values

    func editDevParams(_ index: Int, _ change: (inout DevParams, Track) -> Void) {
        update(track: index) { t in
            var params = t.devOverrides ?? DevParams()
            change(&params, t)
            t.devOverrides = params.isEmpty ? nil : params
        }
    }

    func resetDevOverrides(_ index: Int) {
        update(track: index) { $0.devOverrides = nil }
    }

    func setMetronome(_ change: (inout MetronomeSettings) -> Void) {
        let before = project.metronome
        change(&project.metronome)
        scheduleSave()
        var volumeOnly = before
        volumeOnly.volume = project.metronome.volume
        if volumeOnly == project.metronome {
            engine.metronome.player.volume = Float(MacroCurves.metronomeGain(project.metronome.volume))
            return
        }
        if isPlaying {
            // Restart so the click picks up the new tempo in time with the tracks.
            let position = engine.pause()
            playhead = position
            try? engine.play(from: position, metronome: metronomeIfEnabled)
        }
    }

    private var metronomeIfEnabled: MetronomeSettings? {
        settings.developerMode && project.metronome.enabled ? project.metronome : nil
    }

    private var warmthActive: Bool { settings.developerMode && settings.warmthEnabled }

    private func applyAll() {
        engine.apply(project: project, warmthEnabled: warmthActive)
        if !settings.developerMode {
            engine.master.apply(masterVolume: MacroCurves.volumeUnitySlider)
        }
    }

    // MARK: Cleanup

    func acceptCleanupOffer() {
        guard let index = cleanupOffer else { return }
        cleanupOffer = nil
        // A sensible starting blend; the slider takes it from there.
        if project.tracks[index].cleanup == 0 {
            update(track: index) { $0.cleanup = 0.6 }
        }
        runCleanup(index)
    }

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
            let outcome = await Task.detached(priority: .utility) { () -> Error? in
                do {
                    try CleanupPipeline().render(
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
