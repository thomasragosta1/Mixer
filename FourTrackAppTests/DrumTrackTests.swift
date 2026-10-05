import XCTest
import AVFoundation
import SwiftUI
import UIKit
@testable import FourTrack
import FourTrackCore

/// Runs inside the real app on the simulator, so crashes in the audio graph
/// or SwiftUI show up in CI with a stack trace instead of only on a phone.
@MainActor
final class DrumTrackTests: XCTestCase {
    private var dir: URL!
    private var store: ProjectStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try ProjectStore(rootURL: dir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testDrumSamplesShipInTheApp() {
        for folder in ["studio", "studio-tight", "hand"] {
            for pad in 0..<DrumKit.padCount {
                for take in 1...2 {
                    let url = DrumSamples.directory?.appendingPathComponent("\(folder)/\(pad)_\(take).caf")
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url?.path ?? ""), "\(folder)/\(pad)_\(take).caf missing")
                }
            }
        }
        // Real samples, not the synthesized fallback: the sampled Tight kick is a recording.
        XCTAssertNotNil(DrumSamples.load(kit: .studioTight, pad: 0, variant: 0, sampleRate: 48_000))
    }

    func testAddingDrumTrackAndPlayingPads() throws {
        let project = try store.create(mode: .full)
        let model = ProjectViewModel(project: project, store: store)
        model.activate()
        model.addTrack(kind: .drums)
        XCTAssertTrue(model.isDrumArmed)
        for kit in DrumKit.allCases {
            model.setDrumKit(model.armedTrack, kit)
            for pad in 0..<DrumKit.padCount { model.hitPad(pad) }
            spin(0.2)
        }
        model.close()
    }

    func testDrumScreenRenders() throws {
        // A project whose second lane is an empty drum track: opening it arms
        // that lane, so the drum layout is what gets drawn.
        var project = try store.create(mode: .full)
        project.visibleTrackCount = 2
        project.tracks[1].kind = .drums
        project.tracks[1].name = "Drums"
        let url = store.audioURL(project: project.id, track: 0)
        let w = try CAFWriter(url: url)
        try w.write([Float](repeating: 0.1, count: 48_000))
        try w.finish()
        project.tracks[0].audioFileName = ProjectStore.audioFileName(track: 0)
        try store.save(project)

        let view = NavigationStack {
            ProjectView(project: try! store.load(id: project.id), store: store) { _ in }
        }
        let host = UIHostingController(rootView: view)
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        spin(1.5)
        host.view.layoutIfNeeded()
        window.isHidden = true
    }

    /// The whole track chain (EQ -> in-house compressor -> warmth -> reverb)
    /// must render real audio, at every compressor setting.
    func testTrackChainRendersThroughCompressor() throws {
        var project = try store.create(mode: .full)
        let url = store.audioURL(project: project.id, track: 0)
        let w = try CAFWriter(url: url)
        try w.write((0..<48_000).map { 0.5 * Float(sin(2 * .pi * 220 * Double($0) / 48_000)) })
        try w.finish()
        project.tracks[0].audioFileName = ProjectStore.audioFileName(track: 0)
        store.refreshDurations(&project)
        for slider in [0.0, 0.3, 1.0] {
            project.tracks[0].compressor = slider
            var options = ExportOptions()
            options.format = .wav
            let out = try Exporter.exportTrack(0, project: project, store: store, options: options, warmthEnabled: false) { _ in }
            let file = try AVAudioFile(forReading: out)
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
            try file.read(into: buffer)
            let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
            let peak = samples.map { abs($0) }.max() ?? 0
            XCTAssertGreaterThan(peak, 0.05, "compressor \(slider) rendered silence")
            XCTAssertLessThanOrEqual(peak, 1.0)
        }
    }

    func testUndoRedoRestoresSettingsAndAudio() throws {
        var project = try store.create(mode: .full)
        let url = store.audioURL(project: project.id, track: 0)
        let w = try CAFWriter(url: url)
        try w.write([Float](repeating: 0.25, count: 4_800))
        try w.finish()
        project.tracks[0].audioFileName = ProjectStore.audioFileName(track: 0)
        store.refreshDurations(&project)
        try store.save(project)

        let model = ProjectViewModel(project: project, store: store)
        model.activate()
        XCTAssertFalse(model.canUndo)

        model.toggleMute(0)
        XCTAssertTrue(model.project.tracks[0].mute)
        model.setVolume(0, 0.5)
        model.setVolume(0, 0.4)   // merges with the previous move
        model.deleteTrack(0)      // moves the take into the project's bin
        XCTAssertNil(model.project.tracks[0].audioFileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        model.undo()              // delete
        XCTAssertEqual(model.project.tracks[0].audioFileName, ProjectStore.audioFileName(track: 0))
        XCTAssertEqual(try CAFReader(url: url).frameCount, 4_800, "the take's audio is back")
        XCTAssertEqual(model.project.tracks[0].volume, 0.4, accuracy: 1e-9)
        model.undo()              // both volume moves at once
        XCTAssertEqual(model.project.tracks[0].volume, MacroCurves.volumeUnitySlider, accuracy: 1e-9)
        model.undo()              // mute
        XCTAssertFalse(model.project.tracks[0].mute)
        XCTAssertFalse(model.canUndo)

        model.redo()
        XCTAssertTrue(model.project.tracks[0].mute)
        model.redo()
        XCTAssertEqual(model.project.tracks[0].volume, 0.4, accuracy: 1e-9)
        model.redo()              // the delete again (it clears the slot)
        XCTAssertNil(model.project.tracks[0].audioFileName)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        model.undo()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        model.close()
    }

    /// Pads must sound while the other tracks play, without recording.
    func testPadsPlayAlongWithPlayback() throws {
        var project = try store.create(mode: .full)
        let url = store.audioURL(project: project.id, track: 0)
        let w = try CAFWriter(url: url)
        var tone = [Float](repeating: 0, count: 48_000 * 4)
        let step: Double = 2 * Double.pi * 220 / 48_000
        for i in tone.indices {
            let phase: Double = step * Double(i)
            tone[i] = Float(0.3 * sin(phase))
        }
        try w.write(tone)
        try w.finish()
        project.tracks[0].audioFileName = ProjectStore.audioFileName(track: 0)
        project.visibleTrackCount = 2
        project.tracks[1].kind = .drums
        store.refreshDurations(&project)
        try store.save(project)

        let model = ProjectViewModel(project: project, store: store)
        model.activate()
        model.arm(0)
        model.play()
        XCTAssertTrue(model.isPlaying)
        model.arm(1)              // switch to the drum track while the song plays
        XCTAssertTrue(model.isPlaying, "arming the drums must not stop playback")

        var peak: Float = 0
        let lock = NSLock()
        let mixer = model.engineForTesting.pads.mixer
        mixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            guard let d = buffer.floatChannelData?[0] else { return }
            var m: Float = 0
            for i in 0..<Int(buffer.frameLength) { m = max(m, abs(d[i])) }
            lock.lock(); peak = max(peak, m); lock.unlock()
        }
        for pad in [0, 1, 0, 1] {
            model.hitPad(pad)
            spin(0.15)
        }
        spin(0.4)
        mixer.removeTap(onBus: 0)
        lock.lock(); let heard = peak; lock.unlock()
        XCTAssertGreaterThan(heard, 0.05, "pads were silent during playback")
        XCTAssertTrue(model.isPlaying)
        XCTAssertFalse(model.isRecording)
        XCTAssertTrue(model.project.tracks[1].drumHits.isEmpty, "playing along must not record")
        model.close()
    }

    /// Recording a drum track while the song plays starts from the live spot,
    /// without restarting; adding a track mid-song doesn't stop or rewind it.
    func testPunchInAndAddTrackWhilePlaying() async throws {
        var project = try store.create(mode: .full)
        let url = store.audioURL(project: project.id, track: 0)
        let w = try CAFWriter(url: url)
        try w.write([Float](repeating: 0.1, count: 48_000 * 6))
        try w.finish()
        project.tracks[0].audioFileName = ProjectStore.audioFileName(track: 0)
        store.refreshDurations(&project)
        try store.save(project)

        let model = ProjectViewModel(project: project, store: store)
        model.activate()
        model.play()
        XCTAssertTrue(model.isPlaying)
        spin(1.0)

        model.addTrack(kind: .drums)                 // mid-song
        XCTAssertTrue(model.isPlaying, "adding a track must not stop the song")
        XCTAssertGreaterThan(model.engineForTesting.currentSeconds, 0.5, "adding a track must not rewind")
        XCTAssertTrue(model.isDrumArmed)

        let before = model.engineForTesting.currentSeconds
        await model.startRecording()                 // punch in
        XCTAssertTrue(model.isRecording)
        XCTAssertGreaterThanOrEqual(model.recordingStartSeconds, before - 0.05, "records from the live spot, not 0:00")
        spin(0.3)
        model.hitPad(0)
        spin(0.3)
        model.hitPad(1)
        spin(0.3)
        model.stopRecording()
        spin(1.5)                                    // drum render
        let hits = model.project.tracks[model.armedTrack].drumHits
        XCTAssertEqual(hits.count, 2)
        XCTAssertGreaterThan(hits.first?.time ?? 0, before, "hits land after the punch point")
        model.close()
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
