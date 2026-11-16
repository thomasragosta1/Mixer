import XCTest
import AVFoundation
import SwiftUI
import UIKit
@testable import FourTrack
import FourTrackCore

/// 500 randomized sessions, each driving a project the way a person does:
/// play, scrub, arm, add and delete tracks, mix, drum takes, kits, quantize,
/// undo and redo, Simple and Full mode, the metronome, export, interruptions,
/// closing mid-work and reopening. Every session is seeded, so a crash or a
/// failure names a seed that replays the exact same steps.
///
/// Each step is written to stderr first ("STRESS s=<seed> i=<step> <action>"),
/// so when the app dies the last line in the log is the step that killed it.
@MainActor
final class StressTests: XCTestCase {
    func testScenarios000to049() async throws { try await runSessions(0..<50) }
    func testScenarios050to099() async throws { try await runSessions(50..<100) }
    func testScenarios100to149() async throws { try await runSessions(100..<150) }
    func testScenarios150to199() async throws { try await runSessions(150..<200) }
    func testScenarios200to249() async throws { try await runSessions(200..<250) }
    func testScenarios250to299() async throws { try await runSessions(250..<300) }
    func testScenarios300to349() async throws { try await runSessions(300..<350) }
    func testScenarios350to399() async throws { try await runSessions(350..<400) }
    func testScenarios400to449() async throws { try await runSessions(400..<450) }
    func testScenarios450to499() async throws { try await runSessions(450..<500) }

    /// The core flow with the real microphone path: record, overwrite the
    /// middle, undo. Skipped where the simulator has no microphone.
    func testRecordOverdubAndUndoWithMicrophone() async throws {
        guard StressSession.micUsable else { throw XCTSkip("No microphone permission or input on this simulator") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stress-mic-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore(rootURL: root)
        let project = try store.create(name: "Mic", mode: .simple)
        let model = ProjectViewModel(project: project, store: store)
        model.activate()
        await model.startRecording()
        guard model.isRecording else {
            let why = model.errorMessage ?? "no reason given"
            model.close()
            throw XCTSkip("Recording didn't start here: \(why)")
        }
        stressSpin(1.2)
        model.stopRecording()
        waitForSave(model)
        guard model.project.tracks[0].audioFileName != nil else {
            model.close()
            throw XCTSkip("This simulator's microphone delivered no audio")
        }
        let first = model.duration
        XCTAssertGreaterThan(first, 0.5)

        model.seek(to: 0.3)
        await model.startRecording()
        XCTAssertTrue(model.isRecording)
        stressSpin(0.3)
        model.stopRecording()
        waitForSave(model)
        XCTAssertEqual(model.duration, first, accuracy: 0.1, "recording over the middle keeps what comes after")

        model.undo()
        stressSpin(0.3)
        XCTAssertEqual(model.duration, first, accuracy: 0.1)
        model.undo()
        stressSpin(0.3)
        XCTAssertNil(model.project.tracks[0].audioFileName, "undoing the first take empties the track")
        model.redo()
        stressSpin(0.3)
        XCTAssertNotNil(model.project.tracks[0].audioFileName)
        XCTAssertNil(model.errorMessage)
        model.close()
    }

    private func waitForSave(_ model: ProjectViewModel) {
        let end = Date().addingTimeInterval(5)
        while model.isSaving && Date() < end { stressSpin(0.02) }
    }

    private func runSessions(_ seeds: Range<Int>) async throws {
        var failures: [String] = []
        // Each batch gets a fixed time, so the whole suite can't outrun CI.
        let started = Date()
        let budget: TimeInterval = 120
        var ran = 0
        var slowest: (seed: Int, seconds: TimeInterval) = (seeds.lowerBound, 0)
        defer {
            let total = String(format: "%.1f", Date().timeIntervalSince(started))
            let worst = String(format: "%.1f", slowest.seconds)
            stressLog("batch \(seeds.lowerBound)-\(seeds.upperBound - 1): ran \(ran) of \(seeds.count) sessions in \(total) s; slowest seed \(slowest.seed) took \(worst) s")
        }
        for seed in seeds {
            if Date().timeIntervalSince(started) > budget { break }
            let sessionStart = Date()
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("stress-\(seed)-\(UUID().uuidString)")
            let session = try StressSession(seed: seed, root: root)
            let problems = await session.run()
            ran += 1
            let took = Date().timeIntervalSince(sessionStart)
            if took > slowest.seconds { slowest = (seed, took) }
            for problem in problems {
                stressLog("FAIL seed \(seed): \(problem)")
                failures.append("seed \(seed): \(problem)")
            }
            try? FileManager.default.removeItem(at: root)
        }
        if !failures.isEmpty {
            XCTFail("\(failures.count) problems:\n" + failures.prefix(40).joined(separator: "\n"))
        }
    }
}

/// Unbuffered, so the line is in the log even if the next call crashes.
private func stressLog(_ text: String) {
    fputs("STRESS " + text + "\n", stderr)
}

@MainActor
private func stressSpin(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0xD1B5_4A32_D192_ED03
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private func writeTone(to url: URL, seconds: Double, frequency: Double) throws {
    let count = Int(seconds * 48_000)
    var samples = [Float](repeating: 0, count: count)
    let step: Double = 2 * Double.pi * frequency / 48_000
    for i in 0..<count {
        let phase: Double = step * Double(i)
        samples[i] = Float(0.3 * sin(phase))
    }
    let writer = try CAFWriter(url: url)
    try writer.write(samples)
    try writer.finish()
}

/// One randomized session on one project.
@MainActor
private final class StressSession {
    /// The simulator in CI usually has no microphone; audio takes are only
    /// attempted where recording can really start.
    static var micUsable: Bool = AudioSessionManager.shared.permission == .granted && AVAudioSession.sharedInstance().isInputAvailable

    /// Messages the app shows on purpose in situations these sessions create.
    static let expectedMessages = [
        "All four tracks are in use",
        "Drum tracks are only in Full mode",
        "There's nothing recorded to export yet",
    ]

    let seed: Int
    let store: ProjectStore
    let settings: AppSettings
    let suiteName: String
    let hosted: Bool
    var rng: SeededRNG
    var model: ProjectViewModel
    var window: UIWindow?
    var host: UIViewController?
    var problems: [String] = []
    var stepIndex = 0

    init(seed: Int, root: URL) throws {
        var r = SeededRNG(seed: UInt64(seed))
        let store = try ProjectStore(rootURL: root)
        let suite = "stress.settings.\(seed)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite) ?? .standard)
        settings.developerMode = Int.random(in: 0..<4, using: &r) == 0

        let mode: ProjectMode = Bool.random(using: &r) ? .simple : .full
        var project = try store.create(name: "Stress \(seed)", mode: mode)
        let recorded = Int.random(in: 0...3, using: &r)
        for i in 0..<recorded {
            let seconds = Double.random(in: 0.5...3, using: &r)
            try writeTone(to: store.audioURL(project: project.id, track: i), seconds: seconds, frequency: 180 + 90 * Double(i))
            project.tracks[i].audioFileName = ProjectStore.audioFileName(track: i)
        }
        project.visibleTrackCount = max(1, recorded)
        store.refreshDurations(&project)
        try store.save(project)

        self.seed = seed
        self.store = store
        self.settings = settings
        self.suiteName = suite
        // Every fifth session runs with the real screen around the model, so
        // crashes in the views show up too.
        self.hosted = seed % 5 == 0
        self.rng = r
        self.model = ProjectViewModel(project: try store.load(id: project.id), store: store, settings: settings)
    }

    // MARK: Running

    func run() async -> [String] {
        stressLog("s=\(seed) begin mode=\(model.project.mode.rawValue) tracks=\(model.visibleLanes.count) hosted=\(hosted)")
        open()
        let steps = 18 + pick(14)
        for _ in 0..<steps { await step() }

        if chance(0.35) {
            // Leave (sometimes in the middle of something) and come back.
            if chance(0.5) { settle(3) }
            note("close and reopen")
            closeModel()
            stressSpin(0.15)
            do {
                model = ProjectViewModel(project: try store.load(id: model.project.id), store: store, settings: settings)
            } catch {
                problems.append("couldn't reopen the project: \(error)")
                return finish(checkDisk: false)
            }
            open()
            for _ in 0..<(4 + pick(6)) { await step() }
        }
        return finish(checkDisk: true)
    }

    private func open() {
        if hosted {
            let current = model
            let controller = UIHostingController(rootView: NavigationStack { ProjectView(model: current) })
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            let frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            let w = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: frame)
            w.frame = frame
            w.rootViewController = controller
            w.makeKeyAndVisible()
            window = w
            host = controller
            stressSpin(0.25)
        }
        model.activate()
    }

    private func closeModel() {
        model.close()
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        host = nil
    }

    private func finish(checkDisk: Bool) -> [String] {
        settle(3)
        let end = Date().addingTimeInterval(8)
        while (!model.cleanupProgress.isEmpty || model.exportProgress != nil) && Date() < end { stressSpin(0.05) }
        collect()
        let id = model.project.id
        note("close")
        closeModel()
        // Let anything that finishes after closing land.
        stressSpin(0.3)
        if checkDisk { checkProjectOnDisk(id) }
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        stressLog("s=\(seed) end problems=\(problems.count)")
        return problems
    }

    /// What's on disk must still be a whole project: readable, four tracks,
    /// and every take a track points at really there.
    private func checkProjectOnDisk(_ id: UUID) {
        do {
            let saved = try store.load(id: id)
            if saved.tracks.count != Project.trackCount {
                problems.append("saved project has \(saved.tracks.count) tracks")
            }
            if Set(saved.laneOrder) != Set(0..<Project.trackCount) || saved.laneOrder.count != Project.trackCount {
                problems.append("saved lane order is \(saved.laneOrder)")
            }
            for track in saved.tracks {
                guard let name = track.audioFileName else { continue }
                let url = store.fileURL(name, in: id)
                if !FileManager.default.fileExists(atPath: url.path) {
                    problems.append("track \(track.index + 1) points at \(name), which isn't on disk")
                } else if (try? CAFReader(url: url)) == nil {
                    problems.append("track \(track.index + 1)'s audio file \(name) can't be read")
                }
            }
            for entry in saved.deletedTracks {
                guard let name = entry.track.audioFileName else { continue }
                if !FileManager.default.fileExists(atPath: store.fileURL(name, in: id).path) {
                    problems.append("a deleted track points at \(name), which isn't on disk")
                }
            }
        } catch {
            problems.append("saved project can't be read: \(error)")
        }
    }

    // MARK: Helpers

    private func pick(_ count: Int) -> Int { Int.random(in: 0..<max(1, count), using: &rng) }
    private func unit() -> Double { Double.random(in: 0...1, using: &rng) }
    private func signed() -> Double { Double.random(in: -1...1, using: &rng) }
    private func chance(_ p: Double) -> Bool { unit() < p }

    private func lane() -> Int {
        let lanes = model.visibleLanes
        guard !lanes.isEmpty else { return 0 }
        return lanes[pick(lanes.count)]
    }

    private func note(_ action: String) {
        stressLog("s=\(seed) i=\(stepIndex) \(action)")
    }

    private func settle(_ limit: TimeInterval) {
        let end = Date().addingTimeInterval(limit)
        while model.isSaving && Date() < end { stressSpin(0.02) }
    }

    /// Picks up an error alert the app raised, as a person would see it.
    private func collect() {
        guard let message = model.errorMessage else { return }
        model.errorMessage = nil
        stressLog("s=\(seed) i=\(stepIndex) alert: \(message)")
        if Self.expectedMessages.contains(where: { message.hasPrefix($0) }) { return }
        problems.append("step \(stepIndex) showed an error: \(message)")
    }

    // MARK: Steps

    private func step() async {
        stepIndex += 1
        let m = model
        let roll = pick(100)
        switch roll {
        case 0..<8:
            if m.hasAnyAudio && !m.isSaving {
                note("play/pause")
                m.togglePlay()
            }
        case 8..<13:
            if !m.isSaving {
                switch pick(4) {
                case 0: note("skip back"); m.skip(by: -15)
                case 1: note("skip forward"); m.skip(by: 15)
                case 2: note("return to start"); m.returnToStart()
                default:
                    let target = unit() * (m.duration + 1)
                    note("seek \(target)")
                    m.seek(to: target)
                }
            }
        case 13..<17:
            note("scrub")
            m.beginScrub()
            for _ in 0..<3 {
                m.scrub(to: unit() * (m.duration + 0.5) - 0.2)
                stressSpin(0.01)
            }
            m.endScrub()
        case 17..<24:
            let l = lane()
            note("arm \(l)")
            m.arm(l)
        case 24..<29:
            if !m.isSaving {
                let kind: TrackKind = chance(0.5) ? .drums : .audio
                note("add track \(kind.rawValue)")
                m.addTrack(kind: kind)
            }
        case 29..<34:
            if !m.isSimple {
                let l = lane()
                if chance(0.5) { note("mute \(l)"); m.toggleMute(l) } else { note("solo \(l)"); m.toggleSolo(l) }
            }
        case 34..<44:
            slider()
        case 44..<56:
            await armedTrackAction()
        case 56..<62:
            if !m.isSaving {
                let l = lane()
                note("delete track \(l)")
                m.deleteTrack(l)
            }
        case 62..<66:
            let bin = m.project.deletedTracks
            if !bin.isEmpty {
                let entry = bin[pick(bin.count)]
                if chance(0.7) {
                    note("recover track")
                    m.recoverTrack(entry.id)
                } else {
                    note("delete track permanently")
                    m.deleteTrackPermanently(entry.id)
                }
            }
        case 66..<76:
            if !m.isUndoBlocked {
                if chance(0.65) { note("undo"); m.undo() } else { note("redo"); m.redo() }
            }
        case 76..<79:
            if m.isSimple {
                note("full mode")
                m.switchToFullMode()
            } else if !m.simpleModeBlockedByDrums {
                note("simple mode")
                m.switchToSimpleMode()
            }
        case 79..<86:
            if !m.isSimple && !m.isSaving { metronome() }
        case 86..<88:
            if chance(0.5) {
                let l = lane()
                note("rename track \(l)")
                m.rename(track: l, to: chance(0.2) ? "   " : "Part \(pick(99))")
            } else {
                note("rename project")
                m.renameProject(to: "Song \(pick(99))")
            }
        case 88..<91:
            if !m.isSimple && !m.isSaving {
                note("mixing \(!m.mixMode)")
                m.mixMode.toggle()
                if m.mixMode && chance(0.5) { m.mixPage = lane() }
            }
        case 91..<93:
            let count = m.visibleLanes.count
            if !m.isSaving && count > 1 {
                let from = pick(count)
                let to = pick(count + 1)
                note("move lane \(from) to \(to)")
                m.moveLanes(fromOffsets: IndexSet(integer: from), toOffset: to)
            }
        case 93..<95:
            let l = lane()
            let track = m.project.tracks[l]
            if !track.isEmpty && !track.isDrums {
                note("clean up \(l)")
                m.toggleCleanup(l)
            }
        case 95..<96:
            export()
        case 96..<98:
            sessionEvent()
        case 98..<99:
            note("settings")
            switch pick(3) {
            case 0: settings.developerMode.toggle()
            case 1: settings.warmthEnabled.toggle()
            default: settings.speakerEchoCancellation.toggle()
            }
            m.developerModeChanged()
        default:
            switch pick(4) {
            case 0: note("background"); m.enteredBackground()
            case 1: note("zoom"); m.stepZoom(in: chance(0.5))
            case 2: note("pads hidden toggle"); m.drumPadsHidden.toggle()
            default: note("reset clip"); m.resetClip(pick(Project.trackCount + 1))
            }
        }
        stressSpin(0.015)
        host?.view.layoutIfNeeded()
        collect()
    }

    private func slider() {
        let m = model
        let l = lane()
        let choice = m.isSimple ? 0 : pick(10)
        switch choice {
        case 0:
            note("volume \(l)")
            m.setVolume(l, unit())
        case 1:
            note("eq low \(l)")
            m.setEQ(l, low: signed())
        case 2:
            note("eq mid \(l)")
            m.setEQ(l, mid: signed())
        case 3:
            note("eq high \(l)")
            m.setEQ(l, high: signed())
        case 4:
            note("compressor \(l)")
            m.setCompressor(l, unit())
        case 5:
            note("space \(l)")
            m.setSpace(l, unit())
        case 6:
            note("warmth \(l)")
            m.setWarmth(l, unit())
        case 7:
            if settings.developerMode {
                note("master volume")
                m.setMasterVolume(unit())
            }
        case 8:
            if settings.developerMode {
                note("advanced controls \(l)")
                let ratio = 1 + 10 * unit()
                let gain = 12 * signed()
                m.editDevParams(l) { params, track in
                    var compressor = params.compressor ?? track.resolvedCompressor
                    compressor.ratio = ratio
                    params.compressor = compressor
                    params.inputGainDB = gain
                }
            }
        default:
            if settings.developerMode {
                note("reset to macros \(l)")
                m.resetDevOverrides(l)
            }
        }
    }

    private func metronome() {
        let m = model
        switch pick(7) {
        case 0, 1:
            note("metronome mode")
            m.cycleMetronomeMode()
        case 2:
            note("time signature cycle")
            m.cycleTimeSignature()
        case 3:
            let signature = TimeSignature.more[pick(TimeSignature.more.count)]
            note("time signature \(signature.label)")
            m.setTimeSignature(signature)
        case 4:
            note("tempo nudge")
            m.nudgeTempo(chance(0.5) ? 1 : -1, fine: chance(0.5))
        case 5:
            let bars = pick(3)
            note("count-in \(bars)")
            m.setMetronome { $0.countInBars = bars }
        default:
            let volume = unit()
            note("click volume")
            m.setMetronome { $0.volume = volume }
        }
    }

    /// What the armed track offers: pads, takes, kits and quantize on a drum
    /// track; a take (where there's a microphone) or the drum switch on an audio one.
    private func armedTrackAction() async {
        let m = model
        let armed = m.armedTrack
        let track = m.project.tracks[armed]
        if track.isDrums {
            switch pick(10) {
            case 0..<3:
                let hits = 1 + pick(6)
                note("pads x\(hits)")
                for _ in 0..<hits {
                    m.hitPad(pick(DrumKit.padCount))
                    stressSpin(0.02)
                }
            case 3..<6:
                if !m.isSaving { await drumTake() }
            case 6:
                let kit = DrumKit.allCases[pick(DrumKit.allCases.count)]
                note("kit \(kit.rawValue)")
                m.setDrumKit(armed, kit)
            case 7:
                switch pick(3) {
                case 0:
                    note("quantize toggle")
                    m.toggleQuantize(armed)
                case 1:
                    let division = QuantizeDivision.allCases[pick(QuantizeDivision.allCases.count)]
                    note("quantize \(division.rawValue)")
                    m.setQuantizeDivision(armed, division)
                default:
                    let strength = QuantizeSettings.strengths[pick(QuantizeSettings.strengths.count)]
                    note("quantize strength \(strength)")
                    m.setQuantizeStrength(armed, strength)
                }
            default:
                let pad = pick(DrumKit.padCount)
                let sound = PadSettings(volume: unit(), tune: signed(), decay: unit(), tone: signed())
                note("pad sound \(pad)")
                m.previewPadSettings(track: armed, pad: pad, sound)
                m.hitPad(pad)
                stressSpin(0.02)
                switch pick(3) {
                case 0: m.endPadPreview()
                case 1: m.applyPadSettings(track: armed, pad: pad, sound)
                default: m.revertPad(track: armed, pad: pad)
                }
            }
        } else if track.isEmpty && !m.isSimple && chance(0.4) {
            note("make drum track \(armed)")
            m.setKind(armed, .drums)
        } else if Self.micUsable && !m.isSaving {
            await audioTake()
        } else if !track.isEmpty {
            note("clean up \(armed)")
            m.toggleCleanup(armed)
        }
    }

    private func drumTake() async {
        let m = model
        note("drum take (playing: \(m.isPlaying))")
        if m.project.metronome.enabled && chance(0.5) {
            m.setMetronome { $0.countInBars = 0 }
        }
        await m.startRecording()
        guard m.isRecording else { return }
        let hits = 1 + pick(6)
        for _ in 0..<hits {
            m.hitPad(pick(DrumKit.padCount))
            stressSpin(0.03 + 0.05 * unit())
        }
        endTake()
    }

    private func audioTake() async {
        let m = model
        note("audio take (playing: \(m.isPlaying))")
        if m.project.metronome.enabled && chance(0.5) {
            m.setMetronome { $0.countInBars = 0 }
        }
        await m.startRecording()
        guard m.isRecording else {
            // No working microphone here after all: stop trying, and don't count it.
            if let message = m.errorMessage {
                stressLog("s=\(seed) i=\(stepIndex) microphone unavailable: \(message)")
                m.errorMessage = nil
                Self.micUsable = false
            }
            return
        }
        stressSpin(0.25 + 0.3 * unit())
        endTake()
    }

    /// Takes end the ways they do on a phone: stop, the play button, or a call coming in.
    private func endTake() {
        let m = model
        switch pick(10) {
        case 0:
            note("take ends: interruption")
            AudioSessionManager.shared.onEvent?(.interruptionBegan)
        case 1:
            note("take ends: play button")
            m.togglePlay()
        case 2:
            note("take ends: headphones unplugged")
            AudioSessionManager.shared.onEvent?(.outputDeviceLost)
        default:
            note("take ends: stop")
            m.stopRecording()
        }
        if m.isRecording { m.stopRecording() }
        if chance(0.8) { settle(3) }
    }

    private func export() {
        let m = model
        guard m.hasAnyAudio, m.exportProgress == nil else { return }
        let recorded = m.visibleLanes.filter { !m.project.tracks[$0].isEmpty }
        if chance(0.5) || recorded.isEmpty {
            note("export mix")
            m.export(.mix)
        } else {
            let l = recorded[pick(recorded.count)]
            note("export track \(l)")
            m.export(.track(l))
        }
        let end = Date().addingTimeInterval(30)
        while m.exportProgress != nil && Date() < end { stressSpin(0.05) }
        if m.exportProgress != nil { problems.append("step \(stepIndex): export didn't finish in 30 s") }
        m.exportedURLs = []
    }

    private func sessionEvent() {
        let m = model
        let fire = AudioSessionManager.shared.onEvent
        switch pick(5) {
        case 0:
            note("interruption")
            fire?(.interruptionBegan)
            stressSpin(0.05)
            fire?(.interruptionEnded(shouldResume: true))
        case 1:
            note("output device lost")
            fire?(.outputDeviceLost)
        case 2:
            note("route changed")
            fire?(.routeChanged)
        case 3:
            note("media services reset")
            fire?(.mediaServicesReset)
        default:
            note("engine configuration change")
            NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: m.engineForTesting.engine)
        }
    }
}
