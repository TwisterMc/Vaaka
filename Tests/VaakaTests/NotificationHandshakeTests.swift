import XCTest
import WebKit
@testable import Vaaka

final class NotificationHandshakeTests: XCTestCase {
    func testDocumentStartHandshakeAllowsImmediateBadgePost() {
        let site = Site(id: "hs1", name: "HandshakeTest", url: URL(string: "https://handshake.test")!, favicon: nil)
        let tab = SiteTab(site: site)

        // HTML that posts to badgeUpdate from a head script (runs early)
        let html = """
        <html>
        <head>
        <script>try { window.webkit.messageHandlers.badgeUpdate.postMessage({ count: 42 }); } catch(e) { window.__vaaka_pendingMessages = window.__vaaka_pendingMessages || []; window.__vaaka_pendingMessages.push({ name: 'badgeUpdate', payload: { count: 42 } }); }</script>
        </head>
        <body></body>
        </html>
        """

        let exp = expectation(forNotification: .UnreadChanged, object: nil) { note in
            return (note.object as? String) == site.id
        }

        // Use a data: URL to better emulate a real navigation timing (avoids loadHTMLString ordering quirks)
        let data = html.data(using: .utf8)!
        let b64 = data.base64EncodedString()
        let url = URL(string: "data:text/html;base64,\(b64)")!
        DispatchQueue.main.async {
            _ = tab.webView.load(URLRequest(url: url))
        }

        wait(for: [exp], timeout: 5.0)
        XCTAssertEqual(UnreadManager.shared.count(for: site.id), 42)
    }
}
