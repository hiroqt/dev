import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import dev

final class WebsiteLogoTests: XCTestCase {
    func testLogoCandidatesPreferDeclaredAppleIconAndResolveRelativeURLs() throws {
        let page = try XCTUnwrap(URL(string: "https://site.example.com/about/"))
        let html = #"<link rel="icon" href="/favicon.svg"><link REL='shortcut icon' href='/small.png?v=1&amp;x=2'><link rel=apple-touch-icon href='../large.png'><link rel="icon" href="https://cdn.example.com/icon.png">"#
        let candidates = WebsiteLogoSource.candidates(html: html, pageURL: page)
        XCTAssertEqual(candidates.map(\.absoluteString), [
            "https://site.example.com/large.png",
            "https://site.example.com/small.png?v=1&x=2",
            "https://cdn.example.com/icon.png",
            "https://site.example.com/favicon.ico"
        ])
    }

    func testUnsafeHostsCredentialsAndSchemesNeverBecomeLogoRequests() throws {
        for value in ["http://site.example.com/icon.png", "file:///tmp/icon.png", "https://user:secret@site.example.com/icon.png", "https://localhost/icon.png", "https://127.0.0.1/icon.png", "https://192.168.1.1/icon.png", "https://[::1]/icon.png", "https://office.local/icon.png", "https://site.example.com:8080/icon.png"] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertFalse(WebsiteLogoSource.allowed(url), value)
            XCTAssertNil(WebsiteLogoSource.origin(url), value)
        }
        let root = WebsiteLogoSource.origin(URL(string: "https://site.example.com/path?private=value#fragment"))
        XCTAssertEqual(root?.absoluteString, "https://site.example.com/")
    }

    func testCommentsScriptsUnsafeAssetsAndDuplicatesAreIgnored() throws {
        let root = try XCTUnwrap(URL(string: "https://site.example.com/"))
        let html = #"<!-- <link rel=icon href=https://tracker.example.com/fake.png> --><script>const text='<link rel=icon href=https://tracker.example.com/fake2.png>';</script><link rel=icon href='javascript:alert(1)'><link rel=icon href='http://site.example.com/no.png'><link rel=icon href=/real.png><link rel=icon href=/real.png>"#
        XCTAssertEqual(WebsiteLogoSource.candidates(html: html, pageURL: root).map(\.path), ["/real.png", "/favicon.ico"])
        XCTAssertEqual(WebsiteLogoSource.candidates(html: "", pageURL: root), [root.appending(path: "favicon.ico")])
    }

    func testRasterLogoIsDownsampledAndMalformedOrOversizedDataIsRejected() throws {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 256 * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let source = try XCTUnwrap(context.makeImage())
        let input = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(input, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, source, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let thumbnail = try XCTUnwrap(WebsiteLogoSource.thumbnail(input as Data))
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
        XCTAssertLessThanOrEqual(image.width, 128)
        XCTAssertLessThanOrEqual(image.height, 128)
        XCTAssertNil(WebsiteLogoSource.thumbnail(Data("<svg/>".utf8)))
        XCTAssertNil(WebsiteLogoSource.thumbnail(Data(repeating: 0, count: 2_000_001)))
    }
}
