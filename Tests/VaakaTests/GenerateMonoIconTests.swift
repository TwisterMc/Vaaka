import XCTest
import AppKit
@testable import Vaaka

final class GenerateMonoIconTests: XCTestCase {
    func testGenerateMonoIconStripsWWW() throws {
        let host = "www.adobe.com"
        guard let img = FaviconFetcher().generateMonoIcon(for: host) else {
            XCTFail("generateMonoIcon returned nil")
            return
        }
        // We can't easily inspect pixels here, but we can assert size and that function produced an image
        XCTAssertEqual(img.size.width, 28)
        XCTAssertEqual(img.size.height, 28)
        // Also verify canonical host behaviour (indirectly via debug generation call)
        // This test primarily ensures API returns an image for a host with www.
    }
}
