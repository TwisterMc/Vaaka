import XCTest
import WebKit
@testable import Vaaka

final class TabTests: XCTestCase {
    func testSiteTabHasSafariUserAgent() {
        let site = Site(id: "s1", name: "Example", url: URL(string: "https://example.com")!, favicon: nil)
        let tab = SiteTab(site: site)
        // The customUserAgent should be set to our authoritative Safari UA
        XCTAssertEqual(tab.webView.customUserAgent, UserAgent.safari)
    }
}
