import XCTest
@testable import Vaaka

final class SSODetectorTests: XCTestCase {
    func testKnownIdPHosts() {
        XCTAssertTrue(SSODetector.isSSO(URL(string: "https://accounts.google.com/signin")!))
        XCTAssertTrue(SSODetector.isSSO(URL(string: "https://login.microsoftonline.com/common/oauth2")!))
        XCTAssertTrue(SSODetector.isSSO(URL(string: "https://example.okta.com/app/xyz/sso/saml")!))
    }

    func testSAMLQueryDetection() {
        XCTAssertTrue(SSODetector.isSSO(URL(string: "https://example.com/sso?samlRequest=ABC")!))
        XCTAssertTrue(SSODetector.isSSO(URL(string: "https://idp.example/auth?client_id=foo&redirect_uri=https://app" )!))
    }

    func testNonSSOUrls() {
        XCTAssertFalse(SSODetector.isSSO(URL(string: "https://example.com/about")!))
        XCTAssertFalse(SSODetector.isSSO(URL(string: "https://www.github.com/vaaka")!))
    }
}
