import XCTest

/// Theme colors are fixed and light, but system colors (`.secondary`, a Toggle's label)
/// follow the device. On an iPad in dark mode they turned near-white on the cream
/// background: the settings gear and every category name vanished. Simulators default to
/// light, so the UI walk never sees it; only this key keeps the app light everywhere.
final class AppearanceTests: XCTestCase {
    func testAppStaysLightOnADarkModeDevice() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") as? String, "Light")
    }
}
