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
        let project = try store.create()
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
        var project = try store.create()
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
        var project = try store.create()
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

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
