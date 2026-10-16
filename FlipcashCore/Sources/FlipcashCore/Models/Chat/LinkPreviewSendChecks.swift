//
//  LinkPreviewSendChecks.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// The checks a sender runs before attaching a `LinkPreview` to a message, pinned by
/// `link_preview_send.json`. All lengths and positions are Unicode code points (`unicodeScalars`),
/// as the contract counts them; neither `String.count` nor UTF-16 length does.
public enum LinkPreviewSendChecks {

    public static let maxURLLength = 2048
    public static let maxTitleLength = 256
    public static let maxDescriptionLength = 512

    // MARK: - Whole link -

    /// Whether `url` is a link the contract accepts and appears in `text` as a whole link.
    public static func isWholeLink(url: String, in text: String) -> Bool {
        wholeLinkRange(url: url, in: text) != nil
    }

    /// The UTF-16 range of the first place `url` appears in `text` as a whole link, or `nil` when
    /// it never does or is not a link the contract accepts. An `https://` url whose host has a dot
    /// also matches its bare form, the url less `https://`, which is then the range returned.
    public static func wholeLinkRange(url: String, in text: String) -> NSRange? {
        let link = Array(url.unicodeScalars)
        guard isValidURL(link) else { return nil }
        let haystack = Array(text.unicodeScalars)
        if let range = firstWholeRange(of: link[...], in: haystack) { return range }
        guard let bare = bareForm(of: link) else { return nil }
        return firstWholeRange(of: bare, in: haystack)
    }

    /// The url a preview of `linkText`, a link as written in a message, is sent with: the text
    /// itself, or `https://` and the text for a bare domain.
    public static func previewURL(forLinkText linkText: String) -> String {
        linkText.contains("://") ? linkText : "https://" + linkText
    }

    /// `link` less its `https://`, when the contract lets a text carry it that way: the host has at
    /// least two labels, not counting a trailing dot.
    private static func bareForm(of link: [Unicode.Scalar]) -> ArraySlice<Unicode.Scalar>? {
        guard link.starts(with: "https://".unicodeScalars) else { return nil }
        let rest = link.dropFirst(8)
        var host = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" }
        if host.last == "." { host = host.dropLast() }
        guard host.contains(".") else { return nil }
        return rest
    }

    private static func firstWholeRange(of link: ArraySlice<Unicode.Scalar>, in haystack: [Unicode.Scalar]) -> NSRange? {
        guard !link.isEmpty, haystack.count >= link.count else { return nil }
        var start = 0
        while start <= haystack.count - link.count {
            if haystack[start..<(start + link.count)].elementsEqual(link) {
                var i = start
                while i > 0, openers.contains(haystack[i - 1]) { i -= 1 }
                let before = i == 0 || whiteSpace.contains(haystack[i - 1])
                var j = start + link.count
                while j < haystack.count, trailers.contains(haystack[j]) { j += 1 }
                let after = j == haystack.count || whiteSpace.contains(haystack[j])
                if before && after {
                    let location = haystack[..<start].reduce(0) { $0 + $1.utf16.count }
                    let length = link.reduce(0) { $0 + $1.utf16.count }
                    return NSRange(location: location, length: length)
                }
            }
            start += 1
        }
        return nil
    }

    // MARK: - Cleaning -

    /// The title to send for a scraped `raw` title, or `nil` when nothing visible is left and the
    /// preview must be dropped.
    public static func cleanTitle(_ raw: String) -> String? {
        clean(raw, limit: maxTitleLength, keepLineFeeds: false)
    }

    /// The description to send for a scraped `raw` description; empty for none.
    public static func cleanDescription(_ raw: String) -> String {
        clean(raw, limit: maxDescriptionLength, keepLineFeeds: true) ?? ""
    }

    private static func clean(_ raw: String, limit: Int, keepLineFeeds: Bool) -> String? {
        var out: [Unicode.Scalar] = []
        let scalars = Array(raw.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            i += 1
            switch c.value {
            case 0x0D:
                if i < scalars.count, scalars[i].value == 0x0A { i += 1 }
                out.append(keepLineFeeds ? "\n" : " ")
            case 0x0A, 0x2028, 0x2029:
                out.append(keepLineFeeds ? "\n" : " ")
            case 0x09, 0x0B, 0x0C:
                out.append(" ")
            default:
                if c.properties.generalCategory == .control || bidiEmbeddings.contains(c) { continue }
                out.append(c)
            }
        }
        var s = trim(out[...])
        if s.count > limit { s = s.prefix(limit) }
        s = trim(s)
        guard s.contains(where: { !whiteSpace.contains($0) && $0.properties.generalCategory != .format }) else {
            return nil
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: s)
        return String(view)
    }

    private static func trim(_ s: ArraySlice<Unicode.Scalar>) -> ArraySlice<Unicode.Scalar> {
        var lo = s.startIndex, hi = s.endIndex
        while lo < hi, whiteSpace.contains(s[lo]) { lo += 1 }
        while hi > lo, whiteSpace.contains(s[hi - 1]) { hi -= 1 }
        return s[lo..<hi]
    }

    // MARK: - URL rules -

    private static func isValidURL(_ url: [Unicode.Scalar]) -> Bool {
        guard (1...maxURLLength).contains(url.count) else { return false }
        let rest: ArraySlice<Unicode.Scalar>
        if url.starts(with: "https://".unicodeScalars) {
            rest = url.dropFirst(8)
        } else if url.starts(with: "http://".unicodeScalars) {
            rest = url.dropFirst(7)
        } else {
            return false
        }
        if url.contains(where: { whiteSpace.contains($0) || bidiInURL.contains($0) }) { return false }

        let authority = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if authority.contains("@") { return false }

        var host = authority
        if let colon = authority.lastIndex(of: ":") {
            host = authority[authority.startIndex..<colon]
            let port = authority[(colon + 1)...]
            guard !port.isEmpty, port.allSatisfy({ $0.isASCII && ("0"..."9").contains($0) }),
                  let value = Int(String(String.UnicodeScalarView(port))), (1...65535).contains(value)
            else { return false }
        }
        return isValidHost(host)
    }

    private static func isValidHost(_ host: ArraySlice<Unicode.Scalar>) -> Bool {
        var h = host
        if h.last == "." { h = h.dropLast() }
        guard !h.isEmpty else { return false }
        let labels = h.split(separator: ".", omittingEmptySubsequences: false)
        for label in labels {
            guard !label.isEmpty, label.allSatisfy({ labelScalars.contains($0) }) else { return false }
        }
        let last = labels[labels.count - 1]
        if last.allSatisfy({ ("0"..."9").contains($0) }) { return false }
        if last.count >= 2, last[last.startIndex] == "0", last[last.startIndex + 1] == "x" || last[last.startIndex + 1] == "X",
           last.dropFirst(2).allSatisfy({ $0.properties.isASCIIHexDigit }) {
            return false
        }
        return true
    }

    // MARK: - Character sets -

    private static let whiteSpace: Set<Unicode.Scalar> = Set(
        ([0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
            + Array(0x2000...0x200A)).compactMap(Unicode.Scalar.init)
    )
    private static let openers: Set<Unicode.Scalar> = Set("([{<\"'".unicodeScalars)
    private static let trailers: Set<Unicode.Scalar> = Set(".,;:!?)]}>\"'".unicodeScalars)
    private static let bidiEmbeddings: Set<Unicode.Scalar> = Set(
        (Array(0x202A...0x202E) + Array(0x2066...0x2069)).compactMap(Unicode.Scalar.init)
    )
    private static let bidiInURL: Set<Unicode.Scalar> = bidiEmbeddings.union([0x061C, 0x200E, 0x200F].compactMap(Unicode.Scalar.init))
    private static let labelScalars: Set<Unicode.Scalar> = Set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-".unicodeScalars
    )
}
