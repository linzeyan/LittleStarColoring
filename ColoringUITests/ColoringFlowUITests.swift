import XCTest

/// The whole child journey on the real UI: pick a page, fill, paint with every brush,
/// stamp, erase, undo, go home, restart. Screenshots are kept for human review.
@MainActor
final class ColoringFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        // So the Photos permission question is asked, and answered, on every run.
        app.resetAuthorizationStatus(for: .photos)
        app.launch()
    }

    private func snap(_ name: String) {
        // The whole screen: app.screenshot() of a landscape-only app crops to a square.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func drag(on canvas: XCUIElement, from: CGVector, to: CGVector) {
        canvas.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: to))
    }

    func testColorAPageThenRestartIt() throws {
        launch()
        let vehicles = app.descendants(matching: .any)["category-01-vehicles"]
        XCTAssertTrue(vehicles.waitForExistence(timeout: 10))
        let vehiclesName = vehicles.label
        snap("01-home")

        // Two rows: the first two categories share a column, one above the other.
        let farm = app.descendants(matching: .any)["category-02-farm"]
        XCTAssertEqual(vehicles.frame.midX, farm.frame.midX, accuracy: 1, "the first two categories aren't one column")
        XCTAssertLessThan(vehicles.frame.maxY, farm.frame.minY)

        // Swiped left to the last category, the gear is still there: it used to scroll away.
        let gear = app.descendants(matching: .any)["settings"]
        let scroller = app.scrollViews.firstMatch
        let last = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier ENDSWITH %@", "-constellations")).firstMatch
        // Off screen, a card can still be in the tree, and asking it isHittable is an
        // error rather than false: go by where it is until it's in the window.
        let window = app.windows.firstMatch.frame
        let onScreen = { (card: XCUIElement) in
            card.exists && window.contains(CGPoint(x: card.frame.midX, y: card.frame.midY))
        }
        for _ in 0..<8 where !onScreen(last) { scroller.swipeLeft() }
        XCTAssertTrue(onScreen(last) && last.isHittable, "swiping left never reaches the last category")
        snap("22-home-last")
        XCTAssertTrue(gear.isHittable, "settings scrolled away with the categories")
        // Back from a category, home is exactly where the child left it, not at the start
        // again. A swipe coasts on, so wait for the card to stop before noting where it is.
        var left = last.frame
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.3)
            let now = last.frame
            if now == left { break }
            left = now
        }
        last.tap()
        let back = app.buttons["category-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertTrue(onScreen(last) && last.isHittable, "home came back at the start, not at the last category")
        XCTAssertEqual(last.frame.midX, left.midX, accuracy: 1, "home came back scrolled somewhere else")
        for _ in 0..<8 where !onScreen(vehicles) { scroller.swipeRight() }

        // Settings are for grown-ups: a child's tap on the gear must not open them.
        gear.tap()
        let paintRunsOut = app.switches["setting-paint-runs-out"]
        XCTAssertFalse(paintRunsOut.waitForExistence(timeout: 1.5), "a tap opened settings")
        gear.press(forDuration: 1.5)
        XCTAssertTrue(paintRunsOut.waitForExistence(timeout: 3))
        snap("17-settings")
        let before = paintRunsOut.value as? String
        paintRunsOut.switches.firstMatch.tap()
        XCTAssertNotEqual(paintRunsOut.value as? String, before)
        paintRunsOut.switches.firstMatch.tap()
        XCTAssertEqual(paintRunsOut.value as? String, before)
        app.buttons["settings-close"].tap()
        XCTAssertFalse(paintRunsOut.exists)

        vehicles.tap()
        let card = app.descendants(matching: .any)["page-06-rocket"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // A grown-up playing along can tell which category this is.
        XCTAssertEqual(app.staticTexts["category-title"].label, vehiclesName)
        snap("18-category")
        // The way home stays in reach at the bottom of the pages too.
        scroller.swipeUp()
        XCTAssertTrue(app.buttons["category-back"].isHittable, "home scrolled away with the pages")
        scroller.swipeDown()
        card.tap()
        let canvas = app.descendants(matching: .any)["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let undo = app.buttons["tool-undo"]

        // No tool yet: the side column is put away, and a touch on the canvas does nothing.
        XCTAssertFalse(app.buttons["color-0"].exists, "colors out before a tool was picked")
        XCTAssertFalse(app.buttons["size-0"].exists, "sizes out before a tool was picked")
        XCTAssertFalse(undo.exists, "↶ out before a tool was picked")
        snap("20-no-tool")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()

        app.buttons["tool-bucket"].tap()
        XCTAssertTrue(app.buttons["color-5"].waitForExistence(timeout: 2), "picking the bucket left the colors away")
        XCTAssertFalse(undo.isEnabled, "a touch with no tool changed the page")

        // ⌂ keeps clear of everything a child reaches for: 8 pt from the bucket, a child
        // going for the bucket left the page instead.
        let buttons = try app.snapshot().allButtons
        let home = try XCTUnwrap(buttons.first { $0.identifier == "tool-home" }).frame
        for button in buttons where button.identifier != "tool-home" {
            let dx = max(0, button.frame.minX - home.maxX, home.minX - button.frame.maxX)
            let dy = max(0, button.frame.minY - home.maxY, home.minY - button.frame.maxY)
            XCTAssertGreaterThanOrEqual((dx * dx + dy * dy).squareRoot(), 40, "⌂ crowds \(button.identifier)")
        }

        // ↶ sits beside 🗑, on one row.
        let undoFrame = undo.frame, clearFrame = app.buttons["tool-clear"].frame
        XCTAssertEqual(undoFrame.midY, clearFrame.midY, accuracy: 1, "↶ and 🗑 are on different rows")
        let apart = max(clearFrame.minX - undoFrame.maxX, undoFrame.minX - clearFrame.maxX)
        XCTAssertTrue(apart >= 0 && apart < 16, "↶ is not beside 🗑 (\(apart) pt apart)")
        // 📷 sits left of the toggle, on its row.
        let photoFrame = app.buttons["tool-save-photo"].frame, toggleFrame = app.buttons["side-toggle"].frame
        XCTAssertEqual(photoFrame.midY, toggleFrame.midY, accuracy: 1, "📷 is not on the toggle's row")
        XCTAssertLessThanOrEqual(photoFrame.maxX, toggleFrame.minX, "📷 is not left of the toggle")
        // Six rows of colors, the sizes and ↶ 🗑 all fit on the shortest iPad.
        for id in ["side-toggle", "color-0", "color-custom", "size-custom", "tool-save-photo", "tool-clear"] {
            let frame = app.buttons[id].frame
            XCTAssertTrue(window.contains(frame), "\(id) is cut off at \(frame) in \(window)")
        }

        app.buttons["color-5"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.04)).tap()
        app.buttons["color-0"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(undo.isEnabled)

        // Every brush, two columns of six; the lower ones are reached by scrolling the tools.
        let brushes = ["crayon", "marker", "watercolor", "oil", "ink", "airbrush",
                       "rainbow", "glitter", "stars", "puffy", "chalk", "pencil"]
        let colors = [4, 2, 8, 1, 16, 6]
        for (i, brush) in brushes.enumerated() {
            app.buttons["tool-\(brush)"].tap()
            app.buttons["color-\(colors[i % colors.count])"].tap()
            let x = i < 6 ? 0.06 : 0.54, y = 0.1 + Double(i % 6) * 0.15
            drag(on: canvas, from: CGVector(dx: x, dy: y), to: CGVector(dx: x + 0.4, dy: y + 0.05))
        }
        snap("19-every-brush")

        app.buttons["tool-stamp"].tap()
        let stamp = app.buttons["stamp-0"]
        XCTAssertTrue(stamp.waitForExistence(timeout: 3))
        // Measured now: the lazy list drops a tile once it scrolls away.
        let emojiWidth = stamp.frame.width
        snap("03-stamp-picker")
        // A category shortcut scrolls the one list; it doesn't swap pages.
        app.buttons["stamp-group-2"].tap()
        XCTAssertFalse(stamp.isHittable, "scrolled past the animals")
        snap("15-stamp-shortcut")
        // The category ends with its kaomoji, on tiles wider than the emoji ones.
        // A slow drag, not a swipe: no fling, so it lands the same way every run.
        let kaomoji = app.buttons.matching(NSPredicate(format: "label == %@", "ε=ε=┌( >_<)┘")).firstMatch
        let list = app.scrollViews["stamp-list"]
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        XCTAssertTrue(kaomoji.isHittable, "vehicle kaomoji follow the vehicle emoji")
        XCTAssertGreaterThan(kaomoji.frame.width, emojiWidth)
        snap("16-kaomoji")
        app.buttons["stamp-group-0"].tap()
        XCTAssertTrue(stamp.waitForExistence(timeout: 3) && stamp.isHittable)
        stamp.tap()
        XCTAssertFalse(stamp.exists, "choosing a stamp closes the picker")
        // On the rocket's left outline: the stamp must sit over the line.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.33, dy: 0.4)).tap()
        drag(on: canvas, from: CGVector(dx: 0.1, dy: 0.95), to: CGVector(dx: 0.6, dy: 0.95))

        // The eraser sits low in the scrolling tool list; reaching it must not take ⌂ or ↶
        // out of reach.
        app.buttons["tool-eraser"].tap()
        XCTAssertTrue(app.buttons["tool-home"].isHittable, "⌂ scrolled away with the tools")
        XCTAssertTrue(undo.isHittable, "↶ went out of reach")
        drag(on: canvas, from: CGVector(dx: 0.3, dy: 0.08), to: CGVector(dx: 0.7, dy: 0.3))
        snap("02-canvas")
        undo.tap()
        snap("04-after-undo")

        // Put away and brought back by hand, with the eraser still in hand.
        let toggle = app.buttons["side-toggle"]
        toggle.tap()
        XCTAssertFalse(undo.exists, "the toggle left the side column out")
        XCTAssertFalse(app.buttons["tool-save-photo"].exists, "📷 stayed out with the side column put away")
        snap("21-side-folded")
        toggle.tap()
        let custom = app.buttons["color-custom"]
        XCTAssertTrue(custom.waitForExistence(timeout: 2), "the toggle didn't bring the side column back")

        // The child's own color: the slider changes it, a touch on the canvas closes the panel.
        let firstCustom = custom.value as? String
        custom.tap()
        let hue = app.descendants(matching: .any)["custom-hue"]
        XCTAssertTrue(hue.waitForExistence(timeout: 3))
        hue.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertNotEqual(custom.value as? String, firstCustom, "the hue slider changes the color")
        snap("08-color-panel")
        // All the way to gray: no color left, so the three channels match.
        let vividness = app.descendants(matching: .any)["custom-vividness"]
        vividness.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).tap()
        let gray = try XCTUnwrap(custom.value as? String)
        XCTAssertEqual(Set([1, 3, 5].map { gray.dropFirst($0).prefix(2) }).count, 1, "\(gray) isn't a gray")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
        XCTAssertFalse(hue.exists, "a touch on the canvas closes the panel")
        // Its sliders were opened from the side column, and go away with it.
        custom.tap()
        XCTAssertTrue(hue.waitForExistence(timeout: 3))
        toggle.tap()
        XCTAssertFalse(hue.exists, "the color panel outlived the side column")

        // The child's own size, then a stroke with both.
        app.buttons["tool-marker"].tap()
        XCTAssertTrue(app.buttons["size-custom"].waitForExistence(timeout: 2), "picking a tool left the side column away")
        snap("14-brush-name")
        app.buttons["size-custom"].tap()
        let size = app.descendants(matching: .any)["custom-size"]
        XCTAssertTrue(size.waitForExistence(timeout: 3))
        size.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        snap("09-size-panel")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
        XCTAssertFalse(size.exists)
        drag(on: canvas, from: CGVector(dx: 0.1, dy: 0.62), to: CGVector(dx: 0.55, dy: 0.72))

        // Into Photos once; unchanged since, the button stays off.
        let save = app.buttons["tool-save-photo"]
        save.tap()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            let allow = alert.buttons["Allow"]
            (allow.exists ? allow : alert.buttons.element(boundBy: alert.buttons.count - 1)).tap()
        }
        wait(for: [expectation(for: NSPredicate(format: "value == 'saved'"), evaluatedWith: save)], timeout: 10)
        XCTAssertFalse(save.isEnabled, "nothing new to save")
        snap("10-saved-to-photos")

        // Clear asks first, then wipes the page — and undo brings it all back.
        app.buttons["tool-clear"].tap()
        let wipe = app.buttons["restart-confirm"]
        XCTAssertTrue(wipe.waitForExistence(timeout: 3))
        snap("11-clear-confirm")
        wipe.tap()
        XCTAssertFalse(wipe.exists)
        XCTAssertTrue(save.isEnabled, "a cleared page is something new to save")
        snap("12-cleared")
        undo.tap()
        snap("13-clear-undone")

        // Back to the category the page came from, not all the way home.
        app.buttons["tool-home"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        snap("05-category-with-artwork")

        card.press(forDuration: 1.5)
        let confirm = app.buttons["restart-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        snap("06-restart-confirm")
        confirm.tap()
        XCTAssertFalse(confirm.exists)
        snap("07-category-restarted")

        app.buttons["category-back"].tap()
        XCTAssertTrue(vehicles.waitForExistence(timeout: 5))
    }
}

private extension XCUIElementSnapshot {
    /// Every button on screen from one snapshot: querying frames one by one is a round
    /// trip to the app each.
    var allButtons: [XCUIElementSnapshot] {
        (elementType == .button ? [self] : []) + children.flatMap(\.allButtons)
    }
}
