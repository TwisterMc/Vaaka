import XCTest
import AppKit
@testable import Vaaka

final class FaviconSaveLoadTests: XCTestCase {
    func testSaveAndLoadRoundtrip() throws {
        let fetcher = FaviconFetcher()
        // Create a small red PNG
        let size = NSSize(width: 24, height: 24)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        img.unlockFocus()

        let id = UUID().uuidString
        guard let fname = fetcher.saveImage(img, forSiteID: id) else {
            XCTFail("saveImage returned nil")
            return
        }
        // Ensure file exists on disk
        let file = fetcher.faviconsDir.appendingPathComponent(fname)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        // Loading via image(forResource:)
        if let loaded = fetcher.image(forResource: fname) {
            XCTAssertGreaterThan(loaded.size.width, 0)
        } else {
            XCTFail("image(forResource:) failed to load saved file")
        }
    }
}
