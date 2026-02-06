import XCTest
@testable import MAICore

final class MAITests: XCTestCase {
    func testBrowserConfiguration() {
        let config = BrowserConfiguration()
        XCTAssertTrue(config.enableAdBlocking)
        XCTAssertTrue(config.enablePrivacyMode)
        XCTAssertTrue(config.enableMLPredictions)
    }

    func testBrowserStats() {
        let stats = BrowserStats(
            memoryUsage: 150 * 1024 * 1024,
            cpuUsage: 1.5,
            tabCount: 3,
            moduleCount: 3
        )

        XCTAssertEqual(stats.memoryMB, 150.0, accuracy: 0.1)
        XCTAssertEqual(stats.tabCount, 3)
    }
}
