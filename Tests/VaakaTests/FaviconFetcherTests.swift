import XCTest
import AppKit
@testable import Vaaka

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "MockURLProtocol", code: 1, userInfo: nil))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let d = data {
                client?.urlProtocol(self, didLoad: d)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}

final class FaviconFetcherTests: XCTestCase {
    func testDiscoverAndFetchIconFromHTML() throws {
        let baseURL = URL(string: "https://apple.com")!
        // Prepare an image to return
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Unable to create png data")
            return
        }

        // HTML contains a link rel="icon" href="/assets/icon.png"
        let html = "<html><head><link rel=\"icon\" href=\"/assets/icon.png\"></head><body></body></html>"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else { throw NSError(domain: "MissingURL", code: 1) }
            if url.path == "/" {
                let data = html.data(using: .utf8)
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "text/html"])!
                return (resp, data)
            } else if url.path == "/assets/icon.png" {
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "1.1", headerFields: ["Content-Type": "image/png"])!
                return (resp, png)
            }
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "1.1", headerFields: nil)!
            return (resp, nil)
        }

        let fetcher = FaviconFetcher(session: session)
        let exp = expectation(description: "fetch")
        fetcher.fetchFavicon(for: baseURL) { result in
            XCTAssertNotNil(result)
            exp.fulfill()
        }
        waitForExpectations(timeout: 2.0)
    }
}
