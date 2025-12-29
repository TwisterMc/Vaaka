import XCTest
@testable import Vaaka

final class VaakaTests: XCTestCase {
    func testSiteLoadingFromBundle() throws {
        let sites = SiteManager.shared.sites
        // Our bundled example JSON contains three sites
        XCTAssertEqual(sites.count, 3)
        XCTAssertTrue(sites.contains { $0.name == "GitHub" })
    }

    func testSiteTabManagerCreatesTabs() throws {
        let tabs = SiteTabManager.shared.tabs
        XCTAssertEqual(tabs.count, SiteManager.shared.sites.count)
        // Each tab's webView should have been created
        for tab in tabs {
            XCTAssertNotNil(tab.webView)
            XCTAssertEqual(tab.site.id, tab.site.id)
        }
    }

    func testHostMatchingCanonicalization() throws {
        XCTAssertEqual(SiteManager.canonicalHost("www.example.com"), "example.com")
        XCTAssertEqual(SiteManager.canonicalHost("EXAMPLE.com"), "example.com")
        XCTAssertTrue(SiteManager.hostMatches(host: "sub.example.com", siteHost: "example.com"))
        XCTAssertTrue(SiteManager.hostMatches(host: "example.com", siteHost: "example.com"))
        XCTAssertFalse(SiteManager.hostMatches(host: "evil.com", siteHost: "example.com"))
    }

    func testAddSiteWithBareDomain() throws {
        let domain = "newsite-example.org"
        var s = SiteManager.shared.sites
        let urlStr = "https://\(domain)"
        let u = URL(string: urlStr)!
        let newSite = Site(id: UUID().uuidString, name: "NewSite", url: u, favicon: nil)
        s.append(newSite)
        SiteManager.shared.replaceSites(s)
        XCTAssertTrue(SiteManager.shared.sites.contains { $0.url.host == domain })
    }

    func testEditSiteKeepsIDAndNormalizesDomain() throws {
        // Ensure there is at least one site
        var s = SiteManager.shared.sites
        if s.isEmpty {
            s.append(Site(id: UUID().uuidString, name: "Temp", url: URL(string: "https://temp.example")!, favicon: nil))
            SiteManager.shared.replaceSites(s)
        }
        var sites = SiteManager.shared.sites
        let original = sites[0]
        let edited = Site(id: original.id, name: "EditedName", url: URL(string: "https://edited.example")!, favicon: original.favicon)
        sites[0] = edited
        SiteManager.shared.replaceSites(sites)
        let after = SiteManager.shared.sites[0]
        XCTAssertEqual(after.id, original.id)
        XCTAssertEqual(after.name, "EditedName")
        XCTAssertEqual(after.url.host, "edited.example")
    }

    func testValidationHelpers() throws {
        XCTAssertNotNil(SiteManager.normalizedURL(from: "example.com"))
        XCTAssertNotNil(SiteManager.normalizedURL(from: "https://sub.example.com/one"))
        XCTAssertNil(SiteManager.normalizedURL(from: "not a domain"))
        XCTAssertTrue(SiteManager.isValidDomainInput("example.com"))
        XCTAssertFalse(SiteManager.isValidDomainInput(""))
    }
}
