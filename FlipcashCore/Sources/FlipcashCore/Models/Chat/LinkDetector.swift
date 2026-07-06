//
//  LinkDetector.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Finds the web link (if any) to preview in a chat message's text. Pure and synchronous — wraps
/// `NSDataDetector` and keeps only `http`/`https` matches, so custom schemes (incl. `flipcash://`),
/// `mailto:`, and `tel:` never produce a card.
public struct LinkDetector {

    private let detector: NSDataDetector?

    public init() {
        detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }

    /// The trailing web link in `text`, plus the bubble text to render alongside it. Nil when there's no
    /// web link. When the chosen match is trailing — nothing but whitespace follows it — `bubbleText` is
    /// the text with that link removed and trimmed (an empty result means the message was nothing but
    /// the link). Otherwise the link sits mid-sentence or is followed by more text, so `bubbleText` is
    /// the full original text: the URL stays visible inline and the card still renders below it.
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
        let trailingRemainder = nsText.substring(from: last.range.location + last.range.length)
        let isTrailing = trailingRemainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let bubbleText = if isTrailing {
            nsText.replacingCharacters(in: last.range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return LinkPreview(url: url, bubbleText: bubbleText)
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
