import XCTest

/// Taps through the app like a person: new project, "+", Drum Track, pads.
final class DrumFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testCreateDrumTrackAndPlayPads() {
        let app = XCUIApplication()
        // Press-and-hold tips would sit over the controls being tapped.
        app.launchArguments += ["-hintsDisabled", "YES"]
        app.launch()

        app.buttons["New Project"].firstMatch.tap()
        let create = app.buttons["Create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()

        // New projects default to Simple mode; ⋯ → Simple Mode toggles it.
        XCTAssertTrue(app.buttons["Add Track 2"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Track 1 Volume"].firstMatch.waitForExistence(timeout: 3), "Simple mode is the default and shows a volume bar on each track")
        XCTAssertFalse(app.buttons["Metronome"].exists, "Simple mode hides the metronome")
        app.buttons["More"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Simple Mode"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["Simple Mode"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Metronome"].firstMatch.waitForExistence(timeout: 3), "switched to Full")

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
        // Put the pads away (tap the grabber): every track shows full size, then bring them back.
        let hide = app.descendants(matching: .any)["Hide drum pads"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 3))
        hide.tap()
        let show = app.descendants(matching: .any)["Show drum pads"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 3), "pull tab to bring the pads back is missing")
        XCTAssertFalse(app.buttons["Kick"].exists, "pads should be hidden")
        show.tap()
        XCTAssertTrue(app.buttons["Kick"].firstMatch.waitForExistence(timeout: 3), "pads didn't come back")
        // Metronome: Click → Silent → Off, a time signature tap, tempo arrows.
        let metronome = app.buttons["Metronome"].firstMatch
        XCTAssertTrue(metronome.waitForExistence(timeout: 3))
        metronome.tap(); metronome.tap(); metronome.tap()
        app.buttons["Time signature"].firstMatch.tap()
        app.descendants(matching: .any)["Faster"].firstMatch.tap()
        app.descendants(matching: .any)["Slower"].firstMatch.press(forDuration: 1.2)
        // Turning the metronome on starts it keeping time at once; there's no
        // separate play button any more.
        XCTAssertFalse(app.buttons["Play click"].exists)
        metronome.tap()                      // Click: ticking now
        sleep(1)
        XCTAssertEqual(metronome.value as? String, "Click on")
        metronome.tap(); metronome.tap()     // Silent, then Off

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

    /// Every pad of every kit: a tap in the middle, near each corner, and just
    /// outside its edge (in the gap) plays that pad, and only that pad.
    func testEveryPadPlaysOnlyItself() {
        let app = XCUIApplication()
        app.launchArguments += ["-hintsDisabled", "YES", "-padHitCounts", "YES"]
        app.launch()

        app.buttons["New Project"].firstMatch.tap()
        let create = app.buttons["Create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        XCTAssertTrue(app.buttons["More"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["More"].firstMatch.tap()
        app.buttons["Simple Mode"].firstMatch.tap()
        let add = app.buttons["Add Track 2"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        app.buttons["Drum Track"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Kick"].firstMatch.waitForExistence(timeout: 5))

        let kits: [(String, [String])] = [
            ("Studio", ["Kick", "Snare", "Closed Hat", "Open Hat", "Low Tom", "High Tom", "Ride", "Crash"]),
            ("808", ["Kick", "Snare", "Clap", "Closed Hat", "Open Hat", "Cowbell", "Rim", "Tom"]),
            ("Hand Percussion", ["Cajón", "Slap", "Bongo Low", "Bongo High", "Conga", "Shaker", "Tambourine", "Woodblock"]),
        ]
        // Middle, four corners (inside), and 3 pt into the gap on the right and below.
        let spots: [(CGVector, CGVector)] = [
            (CGVector(dx: 0.5, dy: 0.5), .zero),
            (CGVector(dx: 0.08, dy: 0.08), .zero),
            (CGVector(dx: 0.92, dy: 0.08), .zero),
            (CGVector(dx: 0.08, dy: 0.92), .zero),
            (CGVector(dx: 0.92, dy: 0.92), .zero),
            (CGVector(dx: 1, dy: 0.5), CGVector(dx: 3, dy: 0)),
            (CGVector(dx: 0.5, dy: 1), CGVector(dx: 0, dy: 3)),
        ]
        for (kit, names) in kits {
            app.buttons[kit].firstMatch.tap()
            sleep(1)
            XCTAssertTrue(app.buttons[names[0]].firstMatch.waitForExistence(timeout: 3), "\(kit) pads missing")
            func counts() -> [String: Int] {
                Dictionary(uniqueKeysWithValues: names.map { ($0, Int(app.buttons[$0].firstMatch.value as? String ?? "") ?? -1) })
            }
            for name in names {
                let pad = app.buttons[name].firstMatch
                for (offset, extra) in spots {
                    let before = counts()
                    pad.coordinate(withNormalizedOffset: offset).withOffset(extra).tap()
                    usleep(250_000)
                    let after = counts()
                    for other in names {
                        let expected = (before[other] ?? 0) + (other == name ? 1 : 0)
                        XCTAssertEqual(after[other], expected, "\(kit): tapping \(name) at \(offset)+\(extra) changed \(other)")
                    }
                }
            }
        }
        XCTAssertEqual(app.state, .runningForeground)
    }
}
