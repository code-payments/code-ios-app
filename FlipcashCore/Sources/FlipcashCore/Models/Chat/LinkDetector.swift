//
//  LinkDetector.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Finds the web link (if any) that marks a chat message as link-bearing. Pure and synchronous — wraps
/// `NSDataDetector` and keeps only `http`/`https` matches, so custom schemes (incl. `flipcash://`),
/// `mailto:`, and `tel:` stay plain text.
public struct LinkDetector {

    private let detector: NSDataDetector?

    public init() {
        detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }

    /// The trailing web link in `text`. Nil when there's no web link.
    public func webLink(in text: String) -> LinkPreview? {
        guard let detector else { return nil }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let webMatches = detector.matches(in: text, range: range).filter { match in
            switch match.url?.scheme?.lowercased() {
            case "http", "https":
                // NSDataDetector folds a non-ASCII character glued to the host (e.g. a trailing emoji)
                // into a mangled Punycode host, silently retargeting the link — reject those. A
                // non-ASCII *path* (e.g. /wiki/Café) is fine: it percent-encodes without moving the host.
                Self.authorityIsASCII(nsText.substring(with: match.range))
            default:
                false
            }
        }
        guard let last = webMatches.last, let url = last.url else { return nil }
        return LinkPreview(url: url)
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
