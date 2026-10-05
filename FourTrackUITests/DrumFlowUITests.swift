import XCTest

/// Taps through the app like a person: new project, "+", Drum Track, pads.
final class DrumFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testCreateDrumTrackAndPlayPads() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["New Project"].firstMatch.tap()
        let create = app.buttons["Create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()

        // New projects default to Full mode; ⋯ → Simple Mode toggles it.
        XCTAssertTrue(app.buttons["Add Track 2"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Metronome"].firstMatch.waitForExistence(timeout: 3), "Full mode is the default")
        app.buttons["More"].firstMatch.tap()
        let simple = app.buttons["Simple Mode"].firstMatch
        XCTAssertTrue(simple.waitForExistence(timeout: 3))
        simple.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["Metronome"].exists, "Simple mode hides the metronome")
        XCTAssertTrue(app.descendants(matching: .any)["Track 1 Volume"].firstMatch.waitForExistence(timeout: 3), "Simple mode shows a volume bar on each track")
        app.buttons["More"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Simple Mode"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Simple Mode"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Metronome"].firstMatch.waitForExistence(timeout: 3), "back to Full")

        let add = app.buttons["Add Track 2"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let drum = app.buttons["Drum Track"].firstMatch
        XCTAssertTrue(drum.waitForExistence(timeout: 5))
        drum.tap()

        let kick = app.buttons["Kick"].firstMatch
        XCTAssertTrue(kick.waitForExistence(timeout: 5), "drum pads didn't appear")
        for name in ["Kick", "Snare", "Closed Hat", "Crash"] {
            app.buttons[name].firstMatch.tap()
        }
        // New drum tracks start on Studio · Tight; switch to Roomy and back.
        XCTAssertTrue(app.buttons["Tight"].firstMatch.waitForExistence(timeout: 3), "Studio sound switch missing")
        for sound in ["Roomy", "Tight"] {
            app.buttons[sound].firstMatch.tap()
            sleep(1)
            app.buttons["Kick"].firstMatch.tap()
            app.buttons["Snare"].firstMatch.tap()
        }
        for kit in ["808", "Hand Percussion", "Studio"] {
            app.buttons[kit].firstMatch.tap()
            sleep(1)
            app.buttons[kit == "Hand Percussion" ? "Cajón" : "Kick"].firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["Tight"].firstMatch.exists, "Studio should come back on Tight")
        // Metronome: Click → Silent → Off, a time signature tap, tempo arrows.
        let metronome = app.buttons["Metronome"].firstMatch
        XCTAssertTrue(metronome.waitForExistence(timeout: 3))
        metronome.tap(); metronome.tap(); metronome.tap()
        app.buttons["Time signature"].firstMatch.tap()
        app.descendants(matching: .any)["Faster"].firstMatch.tap()
        app.descendants(matching: .any)["Slower"].firstMatch.press(forDuration: 1.2)
        // The metronome's own play button.
        let playClick = app.buttons["Play click"].firstMatch
        XCTAssertTrue(playClick.waitForExistence(timeout: 3))
        playClick.tap()
        sleep(1)
        XCTAssertTrue(app.buttons["Stop click"].firstMatch.exists, "click preview didn't start")
        app.buttons["Stop click"].firstMatch.tap()

        // Press and hold a pad: its settings bubble, an edit, then revert (asks first).
        app.buttons["Snare"].firstMatch.press(forDuration: 1.2)
        let revert = app.buttons["Revert to Default"].firstMatch
        XCTAssertTrue(revert.waitForExistence(timeout: 5), "pad settings didn't open")
        app.descendants(matching: .any)["Snare tune"].firstMatch.swipeRight()
        sleep(1)
        revert.tap()
        XCTAssertTrue(app.buttons["Are you sure?"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Are you sure?"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Revert to Default"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Done"].firstMatch.tap()
        sleep(1)

        // M, S and Q on the drum track, then undo / redo.
        app.buttons["Mute Drums"].firstMatch.tap()
        app.buttons["Solo Drums"].firstMatch.tap()
        app.buttons["Quantize"].firstMatch.tap()
        let undo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Undo'")).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        for _ in 0..<3 { undo.tap(); usleep(300_000) }
        let redo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Redo'")).firstMatch
        redo.tap()

        // Back to the audio lane and to drums again.
        app.descendants(matching: .any)["Track 1"].firstMatch.tap()
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
