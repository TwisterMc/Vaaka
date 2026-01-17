import XCTest
@testable import Vaaka

final class VaakaTests: XCTestCase {
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

    func testReplaceSitesDedupsByHost() throws {
        // Create two sites with same host but different ids
        let siteA = Site(id: "A", name: "A", url: URL(string: "https://dupe.example.com/path")!, favicon: nil)
        let siteB = Site(id: "B", name: "B", url: URL(string: "https://www.dupe.example.com/other")!, favicon: nil)
        SiteManager.shared.replaceSites([siteA, siteB])
        let after = SiteManager.shared.sites
        // Dedup should keep only the first (siteA)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].id, "A")
    }

    func testSiteTabUpdatesSiteMetadata() throws {
        // Ensure existing SiteTab instance receives updated Site metadata when replaceSites is called
        let site = Site(id: "meta-test", name: "MetaTest", url: URL(string: "https://meta.example.com")!, favicon: nil)
        SiteManager.shared.replaceSites([site])
        let initialTab = SiteTabManager.shared.tabs.first
        XCTAssertNotNil(initialTab)
        // Update site with a favicon
        let updated = Site(id: "meta-test", name: "MetaTest", url: URL(string: "https://meta.example.com")!, favicon: "meta-test.png")
        SiteManager.shared.replaceSites([updated])
        let afterTab = SiteTabManager.shared.tabs.first
        XCTAssertNotNil(afterTab)
        XCTAssertEqual(afterTab?.site.favicon, "meta-test.png")
        // Ensure the original SiteTab instance was reused (same object identity)
        XCTAssertTrue(initialTab === afterTab)
    }

    func testRootDomainHeuristic() throws {
        XCTAssertEqual(SiteManager.rootDomain(for: "mail.google.com"), "google.com")
        XCTAssertEqual(SiteManager.rootDomain(for: "google.com"), "google.com")
        XCTAssertEqual(SiteManager.rootDomain(for: "sub.example.co.uk"), "example.co.uk")
        XCTAssertEqual(SiteManager.rootDomain(for: "a.b.c.d.example.com"), "example.com")
    }

    func testHostMatchingWithSubdomainSite() throws {
        // If a site is added as a specific subdomain, other subdomains of the same root should still match
        XCTAssertTrue(SiteManager.hostMatches(host: "accounts.google.com", siteHost: "mail.google.com"))
        XCTAssertTrue(SiteManager.hostMatches(host: "mail.google.com", siteHost: "mail.google.com"))
        XCTAssertTrue(SiteManager.hostMatches(host: "sub.example.co.uk", siteHost: "mail.example.co.uk"))
        XCTAssertFalse(SiteManager.hostMatches(host: "evil.com", siteHost: "mail.google.com"))
    }
}
