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
        let meet = button(app, "Meet my next animal")
        XCTAssertTrue(meet.waitForExistence(timeout: 10))
        meet.tap()
        tab(app, "Journal")
        XCTAssertTrue(app.staticTexts["13"].waitForExistence(timeout: 5), "12 met + 1")
        let passed = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '7/13' AND label CONTAINS 'quizzes passed'")).firstMatch
        XCTAssertTrue(passed.exists, "6 passed + Red Panda, out of 13 met")
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

    func testImpossibleFocusWarnsInsteadOfBreaking() throws {
        guard let empty = LibraryFacts.emptyCombination else { throw XCTSkip("every kind lives in every place") }
        let app = launch(["-FaunaDemo", "-FaunaTab", "focus"])
        let kind = button(app, LibraryFacts.groupTitles[empty.group]!)
        XCTAssertTrue(kind.waitForExistence(timeout: 10))
        kind.tap()
        let place = button(app, LibraryFacts.regionTitles[empty.region]!)
        XCTAssertTrue(scroll(app, to: place))
        place.tap()
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

    func testAnyJournalAnimalCanBeQuizzed() {
        // The Atlantic Puffin is in the demo journal but its quiz was never taken.
        let app = launch(["-FaunaDemo", "-FaunaTab", "journal"])
        let card = button(app, "Atlantic Puffin,")
        XCTAssertTrue(scroll(app, to: card))
        card.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10), "the article didn't open")
        let take = button(app, "Take the quiz")
        XCTAssertTrue(scroll(app, to: take, maxSwipes: 40), "every journal article ends with its quiz")
        XCTAssertFalse(button(app, "Unlock the next animal").exists, "no floating button outside Today")
        take.tap()
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: 10))
        answerCorrectly(app)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        XCTAssertFalse(button(app, "Meet my next animal").exists, "journal quizzes don't unlock animals")
        app.buttons["Done"].tap()
        XCTAssertTrue(scroll(app, to: button(app, "Retake the quiz")), "and can be taken again")
    }

    func testJournalCanShowOnlyQuizzesToTake() {
        // In the demo, the puffin's quiz was never taken and the axolotl's was passed.
        let app = launch(["-FaunaDemo", "-FaunaTab", "journal"])
        let toTake = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Quiz needed'")).firstMatch
        XCTAssertTrue(toTake.waitForExistence(timeout: 10), "the filter sits above the journal")
        toTake.tap()
        XCTAssertTrue(scroll(app, to: button(app, "Atlantic Puffin,")), "an untaken quiz stays listed")
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(button(app, "Axolotl,").exists, "a passed quiz is hidden")
        for _ in 0..<12 { app.swipeDown() }
        app.buttons["All"].tap()
        XCTAssertTrue(scroll(app, to: button(app, "Axolotl,")), "All shows it again")
    }

    func testJournalCanShowOnlyCompletedQuizzes() {
        let app = launch(["-FaunaDemo", "-FaunaTab", "journal"])
        let completed = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Completed'")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        completed.tap()
        let axolotl = button(app, "Axolotl,")
        XCTAssertTrue(scroll(app, to: axolotl), "a passed quiz is listed")
        XCTAssertTrue(axolotl.label.contains("quiz passed"), "and announced as passed")
        for _ in 0..<8 { app.swipeUp() }
        XCTAssertFalse(button(app, "Atlantic Puffin,").exists, "an untaken quiz is hidden")
    }

    /// In the two-column journal, a tap at the very edge of a card must open that card's animal,
    /// never its neighbour's (wide photos used to spill over and take the tap).
    private func edgeTap(open target: String, neighbour: String, dx: CGFloat) {
        let app = launch(["-FaunaDemo", "-FaunaTab", "journal"])
        let card = button(app, "\(target),")
        let other = button(app, "\(neighbour),")
        XCTAssertTrue(scroll(app, to: card))
        // Bring the row well clear of the tab bar, so the tap lands on the card itself.
        for _ in 0..<6 where card.frame.maxY > app.frame.height * 0.7 {
            app.swipeUp(velocity: .slow)
        }
        sleep(2) // let the photos load, since they're what used to steal taps
        let frames = "\(target) card \(card.frame), \(neighbour) card \(other.frame)"
        card.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
        sleep(3)
        let opened = app.descendants(matching: .any)["Photo of the \(target)"].firstMatch.exists
        let wrong = app.descendants(matching: .any)["Photo of the \(neighbour)"].firstMatch.exists
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "after edge tap on \(target)"
        shot.lifetime = .keepAlways
        add(shot)
        print("EDGE-TAP \(target): opened=\(opened) neighbourOpened=\(wrong) back=\(app.navigationBars.buttons.firstMatch.exists) \(frames)")
        XCTAssertFalse(wrong, "the \(neighbour) opened instead (\(frames))")
        XCTAssertTrue(opened, "the \(target) didn't open (\(frames))")
    }

    func testRightEdgeOfALeftCardOpensThatAnimal() {
        edgeTap(open: "Jaguar", neighbour: "Luna Moth", dx: 0.95)
    }

    func testLeftEdgeOfARightCardOpensThatAnimal() {
        edgeTap(open: "Luna Moth", neighbour: "Jaguar", dx: 0.05)
    }

    // MARK: Accessibility

    func testLargestTextSizeStillWorks() {
        let app = launch(["-FaunaDemo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        openQuiz(app)
        answerCorrectly(app)
        XCTAssertTrue(button(app, "Meet my next animal").waitForExistence(timeout: 10))
        XCTAssertTrue(button(app, "Save it for tomorrow").exists)
    }
}
