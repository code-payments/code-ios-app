//
//  LinkDetector.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// One web link found in a message: where it is, and where it goes.
public struct DetectedLink: Hashable, Sendable, Codable {

    /// UTF-16 offsets into the message text — what `NSRange` and Java's `Matcher` both index,
    /// and what `test-vectors/link_detection.json` stores.
    public let location: Int
    public let length: Int
    public let url: URL

    public var range: NSRange { NSRange(location: location, length: length) }

    public init(range: NSRange, url: URL) {
        self.location = range.location
        self.length = range.length
        self.url = url
    }
}

/// Finds the web links in a chat message. Pure and synchronous — wraps `NSDataDetector` and keeps
/// only `http`/`https` matches, so custom schemes (incl. `flipcash://`), `mailto:`, and `tel:` stay
/// plain text.
public struct LinkDetector {

    private let detector: NSDataDetector?

    public init() {
        detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }

    /// Every web link in `text`, in the order they appear.
    ///
    /// Used to be "the trailing one". Android underlines every match, and a message with two
    /// links looked different on the two platforms for no reason anyone chose — see
    /// `test-vectors/link_detection.json`, which is now the thing that says which is right.
    public func webLinks(in text: String) -> [DetectedLink] {
        guard let detector else { return [] }
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)

        return detector.matches(in: text, range: full).compactMap { match -> DetectedLink? in
            guard let url = match.url else { return nil }
            switch url.scheme?.lowercased() {
            case "http", "https":
                break
            default:
                // Custom schemes (incl. flipcash://), mailto: and tel: stay plain text.
                return nil
            }

            let matchText = nsText.substring(with: match.range)

            // NSDataDetector folds a non-ASCII character glued to the host (e.g. a trailing emoji)
            // into a mangled Punycode host, silently retargeting the link — reject those. A
            // non-ASCII *path* (e.g. /wiki/Café) is fine: it percent-encodes without moving the host.
            guard Self.authorityIsASCII(matchText) else { return nil }

            // The same case seen from the other side. Android's `Patterns.WEB_URL` stops at the
            // last ASCII character and returns a shorter, valid-looking match, so the ASCII-authority
            // check alone would not catch it there. Both platforms apply this boundary instead.
            // Trailing side only: a leading emoji is ordinary message text.
            guard Self.endsOnASCIIBoundary(nsText, end: match.range.location + match.range.length) else {
                return nil
            }

            return DetectedLink(range: match.range, url: Self.normalized(url, matchText: matchText))
        }
    }

    /// The trailing web link in `text`, for callers that want one link rather than the spans.
    public func webLink(in text: String) -> LinkPreview? {
        guard let last = webLinks(in: text).last else { return nil }
        return LinkPreview(url: last.url)
    }

    /// A schemeless match resolves to `https`, not `http`. `NSDataDetector` hands back `http://` for
    /// a bare domain and Android prepends `https://`, and a message that says `flipcash.com/download`
    /// should not become a cleartext link on one platform and a secure one on the other.
    private static func normalized(_ url: URL, matchText: String) -> URL {
        guard !matchText.contains("://"),
              url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = "https"
        return components.url ?? url
    }

    private static func endsOnASCIIBoundary(_ text: NSString, end: Int) -> Bool {
        guard end < text.length else { return true }
        return text.character(at: end) < 0x80
    }

    /// Whether the authority (everything before the first path/query/fragment delimiter) of a matched
    /// URL string is ASCII — the region a glued-on symbol would corrupt into a different host.
    private static func authorityIsASCII(_ matchText: String) -> Bool {
        var authority = Substring(matchText)
        if let schemeSeparator = authority.range(of: "://") {
            authority = authority[schemeSeparator.upperBound...]
        }
        authority = authority.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        return authority.allSatisfy(\.isASCII)
    }
}
