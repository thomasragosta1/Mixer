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
        // Back to the audio lane and to drums again.
        app.descendants(matching: .any)["Track 1"].firstMatch.tap()
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
