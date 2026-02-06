import XCTest
@testable import Vaaka

final class BadgeTitleParsingTests: XCTestCase {
    func testParenthesis() throws {
        XCTAssertEqual(BadgeDetector.parseTitleCount("(3) Slack"), 3)
        XCTAssertEqual(BadgeDetector.parseTitleCount("Slack (12)"), 12)
    }

    func testSquareBrackets() throws {
        XCTAssertEqual(BadgeDetector.parseTitleCount("[2] Inbox"), 2)
    }

    func testBulletAndPipe() throws {
        XCTAssertEqual(BadgeDetector.parseTitleCount("Slack • 4"), 4)
        XCTAssertEqual(BadgeDetector.parseTitleCount("Slack | 5"), 5)
    }

    func testUnreadWord() throws {
        XCTAssertEqual(BadgeDetector.parseTitleCount("Messages (unread 7)"), 7)
        XCTAssertEqual(BadgeDetector.parseTitleCount("Inbox 3 unread"), 3)
    }

    func testFallbackNumber() throws {
        // Conservative: generic embedded numbers should NOT be treated as badges
        XCTAssertEqual(BadgeDetector.parseTitleCount("Foo 8 Bar"), 0)
        XCTAssertEqual(BadgeDetector.parseTitleCount("Inbox — 7"), 7)
        XCTAssertEqual(BadgeDetector.parseTitleCount("3 • Slack"), 3)
    }

    func testRejectsLargeNumbers() throws {
        // Extremely large numbers are capped
        XCTAssertEqual(BadgeDetector.parseTitleCount("(12345) Foo"), 0)
    }

    func testIgnoresNonNumber() throws {
        XCTAssertEqual(BadgeDetector.parseTitleCount("No unread items"), 0)
        XCTAssertEqual(BadgeDetector.parseTitleCount("Report 2026 - Q1"), 0)
        XCTAssertEqual(BadgeDetector.parseTitleCount("Invoice #42 Paid"), 0)
    }
}
