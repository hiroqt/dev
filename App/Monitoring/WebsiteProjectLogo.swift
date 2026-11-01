import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct WebsiteProjectLogo: View {
    let websiteURL: URL?
    var size: CGFloat = 42
    @State private var imageData: Data?

    var body: some View {
        Group {
            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "globe").resizable().scaledToFit().foregroundStyle(.secondary).padding(size * 0.22)
            }
        }
        .frame(width: size, height: size)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: size * 0.2))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .accessibilityHidden(true)
        .task(id: WebsiteLogoSource.origin(websiteURL)) {
            imageData = nil
            guard let origin = WebsiteLogoSource.origin(websiteURL) else { return }
            let data = await WebsiteLogoCache.shared.load(origin)
            if !Task.isCancelled { imageData = data }
        }
    }
}

enum WebsiteLogoSource {
    // shortcut: DNS rebinding is not resolved; pin public addresses before accepting arbitrary untrusted sites.
    static func allowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased(),
              host.contains("."), !host.contains(":"), !host.hasSuffix("."),
              !host.hasSuffix(".localhost"), !host.hasSuffix(".local"), !host.hasSuffix(".internal"),
              !host.hasSuffix(".test"), !host.hasSuffix(".invalid"), !host.hasSuffix(".localdomain"),
              !host.hasSuffix(".lan"), !host.hasSuffix(".home"),
              !host.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }),
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                      && label.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 45 }
              }) else { return false }
        return true
    }

    static func origin(_ url: URL?) -> URL? {
        guard let url, allowed(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func candidates(html: String, pageURL: URL) -> [URL] {
        // shortcut: SVG-only sites use a raster fallback; add a reviewed native SVG decoder when required.
        let html = html.replacingOccurrences(of: #"<!--[\s\S]*?-->|<script\b[^>]*>[\s\S]*?</script\s*>"#, with: "", options: .regularExpression.union(.caseInsensitive))
        let tags = matches(#"<link\b[^>]*>"#, in: html)
        var icons: [(priority: Int, url: URL)] = []
        for tag in tags {
            let attributes = attributes(tag)
            let rel = (attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            guard rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed") || rel.contains("icon"),
                  let href = attributes["href"], let url = URL(string: href, relativeTo: pageURL)?.absoluteURL,
                  allowed(url), url.pathExtension.lowercased() != "svg" else { continue }
            icons.append((rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed") ? 0 : 1, url))
        }
        var seen: Set<URL> = []
        var result = icons.enumerated().sorted {
            $0.element.priority == $1.element.priority ? $0.offset < $1.offset : $0.element.priority < $1.element.priority
        }.map(\.element.url).filter { seen.insert($0).inserted }
        result = Array(result.prefix(3))
        if let origin = origin(pageURL), let fallback = URL(string: "favicon.ico", relativeTo: origin)?.absoluteURL,
           !result.contains(fallback) { result.append(fallback) }
        return result
    }

    private static func attributes(_ tag: String) -> [String: String] {
        guard let expression = try? NSRegularExpression(pattern: #"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#) else { return [:] }
        let text = tag as NSString
        var values: [String: String] = [:]
        for match in expression.matches(in: tag, range: NSRange(location: 0, length: text.length)) {
            let key = text.substring(with: match.range(at: 1)).lowercased()
            let range = (2...4).map { match.range(at: $0) }.first { $0.location != NSNotFound }
            if let range {
                values[key] = text.substring(with: range)
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")
            }
        }
        return values
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let string = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: string.length)).map { string.substring(with: $0.range) }
    }

    static func thumbnail(_ data: Data) -> Data? {
        guard data.count <= 2_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        var selected: (index: Int, pixels: Int)?
        for index in 0..<min(CGImageSourceGetCount(source), 16) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
                  let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
                  width > 0, height > 0, width <= 8192, height <= 8192 else { continue }
            if width * height > (selected?.pixels ?? 0) { selected = (index, width * height) }
        }
        guard let selected, let image = CGImageSourceCreateThumbnailAtIndex(source, selected.index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func fetch(_ origin: URL) async -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: WebsiteLogoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let deadline = Date.now.addingTimeInterval(25)
        let html = try? await read(origin, session: session, limit: 128_000, allowPrefix: true)
        let text = html.map { String(decoding: $0.data, as: UTF8.self) } ?? ""
        let candidates = candidates(html: text, pageURL: html?.url ?? origin)
        for candidate in candidates {
            if Task.isCancelled || Date.now > deadline { return nil }
            if let asset = try? await read(candidate, session: session, limit: 2_000_000, allowPrefix: false),
               let thumbnail = thumbnail(asset.data) { return thumbnail }
        }
        return nil
    }

    private static func read(_ url: URL, session: URLSession, limit: Int, allowPrefix: Bool) async throws -> (data: Data, url: URL) {
        guard allowed(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(allowPrefix ? "text/html" : "image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let finalURL = response.url, allowed(finalURL), allowPrefix || response.expectedContentLength <= limit else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            if data.count == limit {
                if allowPrefix { break }
                throw URLError(.dataLengthExceedsMaximum)
            }
            data.append(byte)
        }
        return (data, finalURL)
    }
}

private actor WebsiteLogoCache {
    static let shared = WebsiteLogoCache()
    private struct Entry { let data: Data?; let expires: Date }
    private var entries: [URL: Entry] = [:]
    private var pending: [URL: Task<Data?, Never>] = [:]
    private var activeLoads = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private func fetchWithSlot(_ origin: URL) async -> Data? {
        if activeLoads >= 12 {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            activeLoads += 1
        }
        defer {
            if waiting.isEmpty { activeLoads -= 1 }
            else { waiting.removeFirst().resume() }
        }
        assert((1...12).contains(activeLoads))
        return await WebsiteLogoSource.fetch(origin)
    }

    func load(_ origin: URL) async -> Data? {
        if let entry = entries[origin], entry.expires > .now { return entry.data }
        if let task = pending[origin] { return await task.value }
        let task = Task { await fetchWithSlot(origin) }
        pending[origin] = task
        let data = await task.value
        pending[origin] = nil
        entries[origin] = Entry(data: data, expires: .now.addingTimeInterval(data == nil ? 300 : 86_400))
        if entries.count > 128, let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key { entries[oldest] = nil }
        return data
    }
}

private final class WebsiteLogoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(WebsiteLogoSource.allowed) == true ? request : nil)
    }
}
