import XCTest

/// App Store screenshots. Not part of the normal test run: the Screenshots
/// workflow runs it on a 6.9-inch simulator with demo projects (synthesized
/// audio, never the person's real projects) and saves each screen.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-demoContent", "YES", "-hintsDisabled", "YES"]
        app.launch()
    }

    private func shot(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ label: String, timeout: TimeInterval = 5) {
        let element = app.descendants(matching: .any)[label].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(label) missing")
        element.tap()
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
    }

    func testCaptureScreens() {
        XCTAssertTrue(app.staticTexts["Late Night Demo"].waitForExistence(timeout: 10))
        shot("01-projects")

        app.staticTexts["Late Night Demo"].tap()
        tap("Skip forward 15 seconds")
        tap("Skip forward 15 seconds")
        tap("Metronome")
        shot("02-tracks")

        app.buttons["Mixing"].firstMatch.tap()
        shot("03-mixing")
        app.buttons["Record"].firstMatch.tap()

        tap("Add Track 4")
        tap("Drum Track")
        XCTAssertTrue(app.buttons["Kick"].firstMatch.waitForExistence(timeout: 5))
        for pad in ["Kick", "Snare", "Closed Hat"] { app.buttons[pad].firstMatch.tap() }
        // Adding a track rewinds; move into the song so the lanes show audio.
        tap("Skip forward 15 seconds")
        tap("Skip forward 15 seconds")
        shot("04-drums")
        back()

        app.staticTexts["Kitchen Jam"].tap()
        tap("Skip forward 15 seconds")
        tap("Skip forward 15 seconds")
        shot("05-simple")

        tap("More")
        tap("Share / Export")
        XCTAssertTrue(app.buttons["Export Mix"].firstMatch.waitForExistence(timeout: 5))
        shot("06-export")
    }
}
