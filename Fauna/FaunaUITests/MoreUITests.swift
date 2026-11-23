import XCTest

/// More end-to-end checks: units in the article, article sections, focus edge cases, large text.
@MainActor
final class MoreUITests: XCTestCase {
    private func launch(_ args: [String] = ["-FaunaDemo"]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = args + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func pill(_ app: XCUIApplication) -> XCUIElement { button(app, "Unlock the next animal") }

    @discardableResult
    private func scroll(_ app: XCUIApplication, to element: XCUIElement, maxSwipes: Int = 25) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let b = app.tabBars.buttons[name]
        XCTAssertTrue(b.waitForExistence(timeout: 10))
        b.tap()
    }

    private func setUnits(_ app: XCUIApplication, _ name: String) {
        tab(app, "Focus")
        let seg = app.buttons[name]
        XCTAssertTrue(scroll(app, to: seg))
        seg.tap()
        tab(app, "Today")
    }

    private func openQuiz(_ app: XCUIApplication) {
        XCTAssertTrue(pill(app).waitForExistence(timeout: 15))
        pill(app).tap()
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: 10))
    }

    private func answerCorrectly(_ app: XCUIApplication, questions: Int = 3) {
        for q in 0..<questions {
            app.buttons["quiz.choice.correct"].firstMatch.tap()
            let next = app.buttons[q < 2 ? "Next question" : "See results"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
    }

    // MARK: Units in the article

    func testImperialFactsInTheArticle() {
        let app = launch()
        setUnits(app, "Imperial")
        XCTAssertTrue(scroll(app, to: any(app, "Weight: 6.6–13 lb")), "Red Panda's 3–6 kg should read in pounds")
    }

    func testMetricFactsInTheArticle() {
        let app = launch()
        setUnits(app, "Metric")
        XCTAssertTrue(scroll(app, to: any(app, "Weight: 3–6 kg")))
    }

    // MARK: Quiz flow

    func testQuizCountsUp() {
        let app = launch()
        openQuiz(app)
        app.buttons["quiz.choice.correct"].tap()
        app.buttons["Next question"].tap()
        XCTAssertTrue(app.staticTexts["2 of 3"].waitForExistence(timeout: 5))
    }

    func testLastQuestionLeadsToResults() {
        let app = launch()
        openQuiz(app)
        for _ in 0..<2 {
            app.buttons["quiz.choice.correct"].tap()
            app.buttons["Next question"].tap()
        }
        app.buttons["quiz.choice.correct"].tap()
        XCTAssertTrue(app.buttons["See results"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Next question"].exists)
    }

    func testPassingCountsInTheJournal() {
        let app = launch()
        openQuiz(app)
        answerCorrectly(app)
        let meet = button(app, "Meet the ")
        XCTAssertTrue(meet.waitForExistence(timeout: 10))
        meet.tap()
        tab(app, "Journal")
        XCTAssertTrue(app.staticTexts["13"].waitForExistence(timeout: 5), "12 met + 1")
        let passed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '7' AND label CONTAINS 'quizzes passed'")).firstMatch
        XCTAssertTrue(passed.exists, "6 passed + Red Panda")
    }

    func testQuizWorksAfterSwitchingToImperial() {
        let app = launch()
        setUnits(app, "Imperial")
        openQuiz(app)
        answerCorrectly(app)
        XCTAssertTrue(app.staticTexts["3 for 3. You really read it."].waitForExistence(timeout: 10))
    }

    // MARK: Article sections

    func testReadingTimeIsShown() {
        let app = launch()
        XCTAssertTrue(scroll(app, to: any(app, "min read")))
    }

    func testConservationStatusIsShown() {
        let app = launch()
        XCTAssertTrue(scroll(app, to: any(app, "Conservation status: Endangered")))
    }

    func testRangeMapIsShown() {
        let app = launch()
        XCTAssertTrue(scroll(app, to: any(app, "Map of the Red Panda's range")))
    }

    func testDidYouKnowCard() {
        let app = launch()
        XCTAssertTrue(scroll(app, to: any(app, "Did you know?")))
    }

    func testDonateLinkNamesTheOrganisation() {
        let app = launch()
        XCTAssertTrue(scroll(app, to: button(app, "Donate at redpandanetwork.org")))
    }

    func testPhotoViewerShowsTheScientificName() {
        let app = launch()
        let photo = app.descendants(matching: .any)["Photo of the Red Panda"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()
        XCTAssertTrue(app.staticTexts["Ailurus fulgens"].waitForExistence(timeout: 10))
    }

    // MARK: Journal and Focus

    func testJournalShowsWhatsStillOutThere() {
        let app = launch(["-FaunaDemo", "-FaunaTab", "journal"])
        XCTAssertTrue(scroll(app, to: any(app, "Still out there")))
    }

    func testFocusExplainsItself() {
        let app = launch(["-FaunaDemo", "-FaunaTab", "focus"])
        XCTAssertTrue(any(app, "bugs in eastern Canada").waitForExistence(timeout: 10))
    }

    func testImpossibleFocusWarnsInsteadOfBreaking() {
        let app = launch(["-FaunaDemo", "-FaunaTab", "focus"])
        let fish = button(app, "Fish")
        XCTAssertTrue(fish.waitForExistence(timeout: 10))
        fish.tap()
        let antarctica = button(app, "Antarctica")
        XCTAssertTrue(scroll(app, to: antarctica))
        antarctica.tap()
        XCTAssertTrue(app.staticTexts["No animals match yet"].waitForExistence(timeout: 5))
        tab(app, "Today")
        XCTAssertTrue(pill(app).waitForExistence(timeout: 10), "Today still works")
    }

    func testSourcesCreditAppleMaps() {
        let app = launch(["-FaunaDemo", "-FaunaTab", "focus"])
        let link = button(app, "Sources & Licenses")
        XCTAssertTrue(scroll(app, to: link))
        link.tap()
        XCTAssertTrue(scroll(app, to: any(app, "Apple Maps imagery")))
    }

    // MARK: Accessibility

    func testLargestTextSizeStillWorks() {
        let app = launch(["-FaunaDemo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openQuiz(app)
        answerCorrectly(app)
        XCTAssertTrue(button(app, "Meet the ").waitForExistence(timeout: 10))
    }
}
