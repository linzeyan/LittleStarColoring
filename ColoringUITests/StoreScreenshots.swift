import XCTest

/// App Store screenshots, not a test: colors pages the way a child might and snaps six
/// screens on the 13-inch iPad. Region points come from tools/store_regions.py.
@MainActor
final class StoreScreenshots: XCTestCase {
    private var app: XCUIApplication!

    // Palette.colors slots.
    private let red = 0, orange = 1, yellow = 2, lightGreen = 3, green = 4, lightBlue = 5, blue = 6
    private let pink = 8, peach = 9, tan = 10, brown = 11, white = 12

    func testStoreScreenshots() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(element("category-01-vehicles").waitForExistence(timeout: 10))
        snap("04-home")

        // The wall: five farm pages colored, the others still waiting.
        openCategory("02-farm")
        openPage("01-cow")
        fill([(0.4521, 0.1714, lightGreen), (0.418, 0.521, tan), (0.645, 0.7471, brown),
              (0.8755, 0.3628, peach), (0.6943, 0.3354, yellow), (0.8379, 0.3213, yellow)])
        closePage()
        openPage("02-pig")
        fill([(0.8301, 0.8296, lightBlue), (0.4634, 0.6235, pink), (0.5488, 0.3428, peach), (0.5513, 0.4541, red)])
        closePage()
        openPage("05-chick")
        fill([(0.165, 0.165, lightBlue), (0.5083, 0.7349, peach), (0.415, 0.4839, yellow), (0.4194, 0.2285, peach),
              (0.522, 0.4448, red), (0.7603, 0.5273, yellow), (0.521, 0.3911, orange)])
        closePage()
        openPage("06-duck")
        fill([(0.2227, 0.2227, lightGreen), (0.5688, 0.5225, yellow), (0.7017, 0.3359, orange),
              (0.6387, 0.8174, orange), (0.3271, 0.8223, orange)])
        closePage()
        openPage("08-dog")
        fill([(0.1753, 0.1753, lightBlue), (0.481, 0.6436, tan), (0.2114, 0.6738, tan), (0.5991, 0.5015, pink)])
        closePage()
        snap("05-wall")
        closeCategory()

        // The hero: one tap per region, then a crayon for the grass.
        openCategory("03-wild")
        openPage("01-lion")
        fill([(0.8501, 0.7886, lightBlue), (0.2725, 0.4678, orange), (0.4805, 0.7676, yellow),
              (0.1602, 0.751, orange), (0.6729, 0.2544, yellow), (0.6035, 0.4834, pink),
              (0.3975, 0.8418, lightBlue), (0.5664, 0.8276, lightBlue)])
        app.buttons["size-2"].tap()
        stroke("crayon", color: green, from: (0.03, 0.935), to: (0.97, 0.935))
        stroke("crayon", color: nil, from: (0.03, 0.965), to: (0.97, 0.965))
        app.buttons["tool-bucket"].tap()
        app.buttons["color-\(orange)"].tap()
        snap("01-canvas")
        closePage()
        closeCategory()

        // The brushes, in the sea.
        openCategory("04-sea")
        openPage("02-whale")
        fill([(0.1885, 0.1885, lightBlue), (0.5327, 0.6045, blue), (0.2983, 0.7622, blue)])
        app.buttons["size-2"].tap()
        stroke("rainbow", color: nil, from: (0.04, 0.32), to: (0.32, 0.04))
        stroke("stars", color: yellow, from: (0.70, 0.06), to: (0.96, 0.24))
        stroke("glitter", color: pink, from: (0.06, 0.42), to: (0.12, 0.80))
        stroke("watercolor", color: white, from: (0.03, 0.90), to: (0.97, 0.88))
        stroke("puffy", color: orange, from: (0.05, 0.955), to: (0.95, 0.955))
        stroke("crayon", color: green, from: (0.94, 0.86), to: (0.96, 0.52))
        snap("02-brushes")
        closePage()
        closeCategory()

        // Stamps around a dinosaur, with the picker open on the animals.
        openCategory("07-dinosaurs")
        openPage("01-t-rex")
        fill([(0.2437, 0.2437, lightBlue), (0.542, 0.4971, orange), (0.3394, 0.7549, orange),
              (0.6689, 0.6035, orange)])
        app.buttons["size-2"].tap()
        stamp("🌴", group: 3, at: [(0.90, 0.60)])
        stamp("🌈", group: 3, at: [(0.70, 0.08)])
        app.buttons["size-1"].tap()
        stamp("🌸", group: 3, at: [(0.10, 0.94), (0.42, 0.95), (0.74, 0.95)])
        stamp("🌼", group: 3, at: [(0.26, 0.95), (0.58, 0.96), (0.90, 0.94)])
        stamp("⭐", group: 3, at: [(0.90, 0.10), (0.80, 0.20)])
        stamp("🦋", group: 0, at: [(0.12, 0.70)])
        app.buttons["tool-stamp"].tap()
        app.buttons["stamp-group-0"].tap()
        snap("03-stamps")
        app.buttons["tool-stamp"].tap()
        closePage()
        closeCategory()

        // The child's own color, used once and its sliders open again.
        openCategory("02-farm")
        openPage("02-pig")
        app.buttons["tool-crayon"].tap()
        app.buttons["color-custom"].tap()
        let hue = element("custom-hue")
        XCTAssertTrue(hue.waitForExistence(timeout: 3))
        hue.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5)).tap()
        tap(0.5, 0.5)
        drag(from: (0.06, 0.94), to: (0.94, 0.94))
        app.buttons["color-custom"].tap()
        XCTAssertTrue(hue.waitForExistence(timeout: 3))
        snap("06-colors")
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private var canvas: XCUIElement { element("canvas") }

    private func snap(_ name: String) {
        // Long enough for the home indicator to fade and a brush's name to go.
        Thread.sleep(forTimeInterval: 3)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func onScreen(_ element: XCUIElement) -> Bool {
        let window = app.windows.firstMatch.frame
        return element.exists && window.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
    }

    private func openCategory(_ id: String) {
        let card = element("category-\(id)")
        let scroller = app.scrollViews.firstMatch
        for _ in 0..<8 where !onScreen(card) { scroller.swipeLeft() }
        for _ in 0..<8 where !onScreen(card) { scroller.swipeRight() }
        card.tap()
        XCTAssertTrue(element("category-back").waitForExistence(timeout: 5), id)
    }

    private func closeCategory() {
        app.buttons["category-back"].tap()
        XCTAssertTrue(element("settings").waitForExistence(timeout: 5))
    }

    private func openPage(_ id: String) {
        let card = element("page-\(id)")
        let scroller = app.scrollViews.firstMatch
        for _ in 0..<4 where !onScreen(card) { scroller.swipeUp() }
        card.tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10), id)
        // Touches before the page has loaded are dropped.
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func closePage() {
        app.buttons["tool-home"].tap()
        XCTAssertTrue(element("category-back").waitForExistence(timeout: 5))
        // The fresh thumbnail lands on the card.
        Thread.sleep(forTimeInterval: 1)
    }

    private func tap(_ x: Double, _ y: Double) {
        canvas.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }

    private func drag(from: (Double, Double), to: (Double, Double)) {
        // Unhurried, so the brush lays down its texture the way a hand would.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: from.0, dy: from.1))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: to.0, dy: to.1)),
                   withVelocity: XCUIGestureVelocity(700), thenHoldForDuration: 0)
    }

    private func fill(_ fills: [(Double, Double, Int)]) {
        app.buttons["tool-bucket"].tap()
        for (x, y, color) in fills {
            app.buttons["color-\(color)"].tap()
            tap(x, y)
        }
    }

    private func stroke(_ brush: String, color: Int?, from: (Double, Double), to: (Double, Double)) {
        app.buttons["tool-\(brush)"].tap()
        if let color { app.buttons["color-\(color)"].tap() }
        drag(from: from, to: to)
    }

    private func stamp(_ emoji: String, group: Int, at points: [(Double, Double)]) {
        app.buttons["tool-stamp"].tap()
        app.buttons["stamp-group-\(group)"].tap()
        // A tile, not the shortcut that shows the same picture.
        let tile = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier MATCHES %@", emoji, "stamp-[0-9]+"))
            .firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 3), emoji)
        tile.tap()
        for (x, y) in points { tap(x, y) }
    }
}
