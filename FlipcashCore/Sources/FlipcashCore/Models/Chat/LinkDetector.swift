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
                // NSDataDetector folds a glued-on non-ASCII character (e.g. an emoji) into a Punycode
                // host, mangling the URL — reject the match rather than preview a URL nobody typed.
                nsText.substring(with: match.range).allSatisfy(\.isASCII)
            default:
                false
            }
        }
        guard let last = webMatches.last, let url = last.url else { return nil }
        return LinkPreview(url: url)
    }
}
