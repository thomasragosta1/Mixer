import XCTest

/// Drives the real app in the simulator. `-FaunaDemo` starts with sample history (Red Panda today,
/// 12 animals met); `-FaunaOnboarding` starts fresh. Neither touches saved progress.
@MainActor
final class FaunaUITests: XCTestCase {

    // MARK: Helpers

    private func launch(_ args: String...) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = args + ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// Labels of buttons can start with an icon's name, so match on what they contain.
    private func element(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func unlockPill(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Unlock the next animal'")).firstMatch
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no \(name) tab")
        button.tap()
    }

    /// Scrolls the frontmost scroll view until `element` is on screen.
    @discardableResult
    private func scroll(_ app: XCUIApplication, to element: XCUIElement, maxSwipes: Int = 25) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    /// Waits until an element can actually be tapped (not mid-animation), then taps it.
    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(element) never appeared")
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isHittable && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        element.tap()
    }

    private func openQuiz(_ app: XCUIApplication) {
        let pill = unlockPill(app)
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "no unlock button on Today")
        pill.tap()
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: 10), "quiz didn't open")
    }

    /// Answers the open quiz; `wrong` lists the questions (0-based) to get wrong.
    private func answer(_ app: XCUIApplication, wrong: Set<Int> = []) {
        for q in 0..<3 {
            let id = wrong.contains(q) ? "quiz.choice.wrong" : "quiz.choice.correct"
            let choice = app.buttons[id].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 10), "question \(q + 1) has no \(id)")
            choice.tap()
            let next = app.buttons[q < 2 ? "Next question" : "See results"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
    }

    private func passAndMeetNext(_ app: XCUIApplication) -> String {
        openQuiz(app)
        answer(app)
        XCTAssertTrue(app.staticTexts["3 for 3. You really read it."].waitForExistence(timeout: 10))
        let meet = button(app, containing: "Meet the ")
        XCTAssertTrue(meet.waitForExistence(timeout: 10))
        // "Meet the Okapi, The forest giraffe…" -> "Okapi"
        let label = meet.label
        let name = label.components(separatedBy: "Meet the ").last?.components(separatedBy: ",").first ?? label
        meet.tap()
        return name.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Onboarding

    func testOnboardingWelcome() {
        let app = launch("-FaunaOnboarding")
        XCTAssertTrue(app.staticTexts["Fauna"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["One remarkable animal, every day."].exists)
        XCTAssertTrue(app.buttons["Get started"].exists)
    }

    func testOnboardingSurpriseMeLandsOnToday() {
        let app = launch("-FaunaOnboarding")
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.staticTexts["68 animals to discover"].waitForExistence(timeout: 5))
        app.buttons["Surprise me"].tap()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 5))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(unlockPill(app).waitForExistence(timeout: 10))
    }

    func testOnboardingChoosingAKindChangesTheButton() {
        let app = launch("-FaunaOnboarding")
        app.buttons["Get started"].tap()
        let birds = button(app, containing: "Birds")
        XCTAssertTrue(birds.waitForExistence(timeout: 5))
        birds.tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["12 animals to discover"].exists)
        XCTAssertFalse(app.buttons["Surprise me"].exists)
    }

    func testOnboardingBugsInEasternNorthAmerica() {
        let app = launch("-FaunaOnboarding")
        app.buttons["Get started"].tap()
        tapWhenReady(button(app, containing: "Insects & Bugs"))
        XCTAssertTrue(app.staticTexts["8 animals to discover"].waitForExistence(timeout: 5))
        let east = button(app, containing: "Eastern North America")
        scroll(app, to: east)
        tapWhenReady(east)
        XCTAssertTrue(app.staticTexts["5 animals to discover"].waitForExistence(timeout: 5))
        tapWhenReady(app.buttons["Continue"])
        tapWhenReady(app.buttons["Not now"])
        XCTAssertTrue(unlockPill(app).waitForExistence(timeout: 10))
        let bugs = ["Monarch Butterfly", "Rusty Patched Bumble Bee", "Luna Moth", "Common Eastern Firefly", "Common Green Darner"]
        XCTAssertTrue(bugs.contains { app.staticTexts[$0].exists }, "today's animal isn't an eastern bug")
    }

    // MARK: Today and the quiz

    func testTodayShowsTheDailyAnimal() {
        let app = launch("-FaunaDemo")
        XCTAssertTrue(app.staticTexts["Red Panda"].waitForExistence(timeout: 10))
        XCTAssertTrue(unlockPill(app).exists)
        XCTAssertTrue(app.buttons["Share"].exists)
    }

    func testUnlockOpensTheQuiz() {
        let app = launch("-FaunaDemo")
        openQuiz(app)
        XCTAssertTrue(element(app, containing: "About the Red Panda").exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'quiz.choice'")).count, 4)
    }

    func testClosingTheQuizReturnsToTheArticle() {
        let app = launch("-FaunaDemo")
        openQuiz(app)
        app.buttons["Close"].tap()
        XCTAssertTrue(unlockPill(app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Red Panda"].exists, "closing must not change today's animal")
    }

    func testCorrectAnswerFeedback() {
        let app = launch("-FaunaDemo")
        openQuiz(app)
        app.buttons["quiz.choice.correct"].tap()
        XCTAssertTrue(app.staticTexts["Exactly right."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next question"].exists)
    }

    func testWrongAnswerRevealsTheRightOne() {
        let app = launch("-FaunaDemo")
        openQuiz(app)
        app.buttons["quiz.choice.wrong"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Not quite."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["quiz.choice.correct"].value as? String, "Correct answer")
        XCTAssertFalse(app.buttons["quiz.choice.correct"].isEnabled, "answers lock after a pick")
    }

    func testPassingUnlocksTheNextAnimal() {
        let app = launch("-FaunaDemo")
        let name = passAndMeetNext(app)
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10), "Today should show the \(name)")
        XCTAssertFalse(element(app, containing: "About the Red Panda").exists)
        XCTAssertTrue(unlockPill(app).waitForExistence(timeout: 10), "you can keep going")
    }

    func testOneWrongAnswerMeansTryAgain() {
        let app = launch("-FaunaDemo")
        openQuiz(app)
        answer(app, wrong: [1])
        XCTAssertTrue(app.staticTexts["2 of 3. So close."].waitForExistence(timeout: 5))
        app.buttons["Try the questions again"].tap()
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: 5))
    }

    func testReadItAgainGoesBackToTheArticle() {
        let app = launch("-FaunaDemo")
        openQuiz(app)
        answer(app, wrong: [0, 1, 2])
        XCTAssertTrue(app.staticTexts["0 of 3. So close."].waitForExistence(timeout: 5))
        app.buttons["Read it again"].tap()
        XCTAssertTrue(app.staticTexts["Red Panda"].waitForExistence(timeout: 5))
        XCTAssertTrue(unlockPill(app).exists)
    }

    func testThreeUnlocksInARow() {
        let app = launch("-FaunaDemo")
        var names: Set<String> = []
        for _ in 0..<3 { names.insert(passAndMeetNext(app)) }
        XCTAssertEqual(names.count, 3, "each unlock should bring a different animal")
        tab(app, "Journal")
        XCTAssertTrue(app.staticTexts["15"].waitForExistence(timeout: 5), "12 met + 3 unlocked")
    }

    func testPhotoViewerOpensAndCloses() {
        let app = launch("-FaunaDemo")
        let photo = app.descendants(matching: .any)["Photo of the Red Panda"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(unlockPill(app).waitForExistence(timeout: 5))
    }

    func testArticleEndsWithAttributionAndHelp() {
        let app = launch("-FaunaDemo")
        XCTAssertTrue(scroll(app, to: element(app, containing: "Help the Red Panda")), "no Help section")
        let wiki = button(app, containing: "Read the full article on Wikipedia")
        XCTAssertTrue(scroll(app, to: wiki), "no link to Wikipedia")
        XCTAssertTrue(element(app, containing: "CC BY-SA 4.0").exists, "no license notice")
    }

    func testUnlockCardAtTheEndOfTheArticle() {
        let app = launch("-FaunaDemo")
        let card = element(app, containing: "Curious for more?")
        XCTAssertTrue(scroll(app, to: card))
        button(app, containing: "Unlock another animal").tap()
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: 10))
    }

    // MARK: Journal

    func testJournalShowsProgress() {
        let app = launch("-FaunaDemo", "-FaunaTab", "journal")
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["12"].exists)
        XCTAssertTrue(app.staticTexts["of 68 animals discovered"].exists)
    }

    func testJournalTodayCardOpensToday() {
        let app = launch("-FaunaDemo", "-FaunaTab", "journal")
        let card = button(app, containing: "Red Panda,")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        // Tap near the edge next to the neighbouring card, where a wide photo used to steal taps.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(unlockPill(app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected, "should switch to Today")
        XCTAssertTrue(app.staticTexts["Red Panda"].exists, "Today should show today's animal")
        XCTAssertFalse(app.navigationBars["Journal"].exists)
    }

    func testJournalOpensAPastAnimal() {
        let app = launch("-FaunaDemo", "-FaunaTab", "journal")
        let card = button(app, containing: "Axolotl,")
        XCTAssertTrue(scroll(app, to: card))
        card.tap()
        XCTAssertTrue(app.staticTexts["Axolotl"].waitForExistence(timeout: 10))
        XCTAssertFalse(unlockPill(app).exists, "past animals don't unlock new ones")
    }

    func testRetakingAPassedQuizIsPracticeOnly() {
        let app = launch("-FaunaDemo", "-FaunaTab", "journal")
        let card = button(app, containing: "Axolotl,")
        XCTAssertTrue(scroll(app, to: card))
        card.tap()
        let retake = button(app, containing: "Retake the quiz")
        XCTAssertTrue(scroll(app, to: retake), "passed quizzes can be retaken")
        retake.tap()
        XCTAssertTrue(app.staticTexts["1 of 3"].waitForExistence(timeout: 10))
        answer(app)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        XCTAssertFalse(button(app, containing: "Meet the ").exists, "practice must not unlock an animal")
        app.buttons["Done"].tap()
        tab(app, "Journal")
        XCTAssertTrue(app.staticTexts["12"].waitForExistence(timeout: 5))
    }

    func testLockedTileSendsYouToToday() {
        let app = launch("-FaunaDemo", "-FaunaTab", "journal")
        let locked = button(app, containing: "Undiscovered")
        XCTAssertTrue(scroll(app, to: locked))
        locked.tap()
        XCTAssertTrue(unlockPill(app).waitForExistence(timeout: 10))
    }

    // MARK: Focus

    func testFocusListsKindsAndPlaces() {
        let app = launch("-FaunaDemo", "-FaunaTab", "focus")
        XCTAssertTrue(app.navigationBars["Focus"].waitForExistence(timeout: 10))
        XCTAssertTrue(button(app, containing: "Mammals").exists)
        XCTAssertTrue(button(app, containing: "Africa").exists)
        XCTAssertTrue(app.staticTexts["68 animals match"].exists)
    }

    func testFocusChipUpdatesTheCount() {
        let app = launch("-FaunaDemo", "-FaunaTab", "focus")
        let birds = button(app, containing: "Birds")
        XCTAssertTrue(birds.waitForExistence(timeout: 10))
        birds.tap()
        XCTAssertTrue(app.staticTexts["12 animals match"].waitForExistence(timeout: 5))
        birds.tap()
        XCTAssertTrue(app.staticTexts["68 animals match"].waitForExistence(timeout: 5))
    }

    func testUnitsSetting() {
        let app = launch("-FaunaDemo", "-FaunaTab", "focus")
        let imperial = app.buttons["Imperial"]
        XCTAssertTrue(scroll(app, to: imperial))
        imperial.tap()
        XCTAssertTrue(app.staticTexts["Feet, pounds, miles."].waitForExistence(timeout: 5))
        app.buttons["Metric"].tap()
        XCTAssertTrue(app.staticTexts["Metres, kilograms, kilometres."].waitForExistence(timeout: 5))
    }

    func testSourcesAndLicenses() {
        let app = launch("-FaunaDemo", "-FaunaTab", "focus")
        let link = button(app, containing: "Sources & Licenses")
        XCTAssertTrue(scroll(app, to: link))
        link.tap()
        XCTAssertTrue(element(app, containing: "Creative Commons BY-SA 4.0").waitForExistence(timeout: 10))
        let credit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Photo: ' AND NOT (label CONTAINS 'Wikimedia Commons')")).firstMatch
        XCTAssertTrue(credit.waitForExistence(timeout: 15), "photo credits should name authors")
    }

    func testResetJournal() {
        let app = launch("-FaunaDemo", "-FaunaTab", "focus")
        let reset = app.buttons["Reset journal"]
        XCTAssertTrue(scroll(app, to: reset))
        let listFrame = reset.frame
        reset.tap()
        // The confirmation adds a second "Reset journal" button; tap that one, not the list row.
        let deadline = Date().addingTimeInterval(5)
        var confirm: XCUIElement?
        while confirm == nil && Date() < deadline {
            confirm = app.buttons.matching(identifier: "Reset journal").allElementsBoundByIndex
                .first { $0.frame != listFrame && $0.isHittable }
            if confirm == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
        }
        XCTAssertNotNil(confirm, "no confirmation before erasing progress")
        confirm?.tap()
        tab(app, "Journal")
        XCTAssertTrue(app.staticTexts["1"].waitForExistence(timeout: 5), "only today's animal remains")
    }

    // MARK: Stress

    func testRapidTabSwitching() {
        let app = launch("-FaunaDemo")
        for i in 0..<30 { tab(app, ["Today", "Journal", "Focus"][i % 3]) }
        tab(app, "Today")
        XCTAssertTrue(unlockPill(app).waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testRepeatedLaunches() {
        for _ in 0..<5 {
            let app = launch("-FaunaDemo")
            XCTAssertTrue(unlockPill(app).waitForExistence(timeout: 15))
            app.terminate()
        }
    }

    func testRapidQuizOpenAndClose() {
        let app = launch("-FaunaDemo")
        for _ in 0..<8 {
            openQuiz(app)
            app.buttons["Close"].tap()
        }
        XCTAssertTrue(app.staticTexts["Red Panda"].waitForExistence(timeout: 5))
    }
}
