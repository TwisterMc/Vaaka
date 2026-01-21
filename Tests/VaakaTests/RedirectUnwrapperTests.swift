import XCTest
@testable import Vaaka

final class RedirectUnwrapperTests: XCTestCase {
    func testGmailDataSaferedirecturl() throws {
        let raw = "https://mail.google.com/mail/u/0/?ui=2&ik=abc&attid=0.1&view=att&th=123&data-saferedirecturl=https%3A%2F%2Fexample.com%2Fpath"
        let u = URL(string: raw)!
        let un = RedirectUnwrapper.unwrap(u)
        XCTAssertNotNil(un)
        XCTAssertEqual(un?.host, "example.com")
        XCTAssertEqual(un?.path, "/path")
    }

    func testFacebookLinkShim() throws {
        let raw = "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Ffoo&h=abc"
        let u = URL(string: raw)!
        let un = RedirectUnwrapper.unwrap(u)
        XCTAssertNotNil(un)
        XCTAssertEqual(un?.host, "example.com")
        XCTAssertEqual(un?.path, "/foo")
    }

    func testOutlookSafeLinks() throws {
        let raw = "https://safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2Ftest&data=abc"
        let u = URL(string: raw)!
        let un = RedirectUnwrapper.unwrap(u)
        XCTAssertNotNil(un)
        XCTAssertEqual(un?.host, "example.com")
        XCTAssertEqual(un?.path, "/test")
    }

    func testProofpointUrldefense() throws {
        let raw = "https://urldefense.proofpoint.com/v2/url?u=https%3A%2F%2Fexample.com%2Fhello"
        let u = URL(string: raw)!
        let un = RedirectUnwrapper.unwrap(u)
        XCTAssertNotNil(un)
        XCTAssertEqual(un?.host, "example.com")
    }

    func testShortenerTcoReturnsOriginal() throws {
        let raw = "https://t.co/abcdef"
        let u = URL(string: raw)!
        let un = RedirectUnwrapper.unwrap(u)
        XCTAssertNotNil(un)
        XCTAssertEqual(un, u)
    }

    func testGenericUrlParamFallback() throws {
        let raw = "https://example-wrapper.com/go?target=https%3A%2F%2Fexample.org%2Fok"
        let u = URL(string: raw)!
        let un = RedirectUnwrapper.unwrap(u)
        XCTAssertNotNil(un)
        XCTAssertEqual(un?.host, "example.org")
    }

    func testRejectsNonHttpSchemes() throws {
        let raw = "https://mail.google.com/?data-saferedirecturl=javascript%3Aalert(1)"
        let u = URL(string: raw)!
        let un = RedirectUnwrapper.unwrap(u)
        XCTAssertNil(un)
    }
}
