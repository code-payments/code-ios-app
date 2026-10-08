//
//  WebPageParser.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Reads a page's head into card metadata, held to `link_metadata.json` so both apps agree.
public nonisolated enum WebPageParser {

    /// The title, description and image the page's head offers, or nil when it has no title.
    public static func parse(_ body: Data, finalURL: URL) -> LinkCard.Web.Resolved? {
        let text = String(decoding: body, as: UTF8.self)
        let head = scanHead(text)
        guard let title = clean(head.meta["og:title"] ?? head.title),
              let rawHost = WebLinks.host(of: finalURL) else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        return LinkCard.Web.Resolved(
            title: title,
            description: clean(head.meta["og:description"] ?? head.meta["description"]),
            imageURL: head.meta["og:image"].flatMap { imageURL($0, relativeTo: finalURL) },
            host: host
        )
    }

    // MARK: - Scanning -

    private struct Head {
        var title: String?
        var meta: [String: String] = [:]
    }

    private static let wanted: Set<String> = ["og:title", "og:description", "og:image", "description"]

    private static func scanHead(_ text: String) -> Head {
        let bytes = text.utf8
        let end = headEnd(bytes)
        var head = Head()
        var i = bytes.startIndex
        while i < end {
            guard bytes[i] == UInt8(ascii: "<") else { i = bytes.index(after: i); continue }
            let next = bytes.index(after: i)
            if matches("meta", at: next, in: bytes, end: end) {
                i = readMeta(from: bytes.index(next, offsetBy: 4), in: bytes, end: end, into: &head)
            } else if matches("title", at: next, in: bytes, end: end) {
                i = readTitle(from: bytes.index(next, offsetBy: 5), in: bytes, end: end, into: &head)
            } else {
                i = next
            }
        }
        return head
    }

    /// The first `</head` or `<body`, else the end of the document.
    private static func headEnd(_ bytes: String.UTF8View) -> String.Index {
        var i = bytes.startIndex
        while i < bytes.endIndex {
            if bytes[i] == UInt8(ascii: "<") {
                let next = bytes.index(after: i)
                if matches("/head", at: next, in: bytes, end: bytes.endIndex)
                    || matches("body", at: next, in: bytes, end: bytes.endIndex) { return i }
            }
            i = bytes.index(after: i)
        }
        return bytes.endIndex
    }

    /// Whether `word` (lowercase ASCII) sits at `index`, ignoring case, and is a whole tag name.
    private static func matches(_ word: StaticString, at index: String.Index, in bytes: String.UTF8View, end: String.Index) -> Bool {
        var i = index
        for expected in UnsafeBufferPointer(start: word.utf8Start, count: word.utf8CodeUnitCount) {
            guard i < end, lower(bytes[i]) == expected else { return false }
            i = bytes.index(after: i)
        }
        guard i < end else { return true }
        let b = bytes[i]
        return isSpace(b) || b == UInt8(ascii: ">") || b == UInt8(ascii: "/")
    }

    private static func readMeta(from start: String.Index, in bytes: String.UTF8View, end: String.Index, into head: inout Head) -> String.Index {
        var attributes: [String: String] = [:]
        var i = start
        while i < end, bytes[i] != UInt8(ascii: ">") {
            if isSpace(bytes[i]) || bytes[i] == UInt8(ascii: "/") { i = bytes.index(after: i); continue }
            let nameStart = i
            while i < end, !isSpace(bytes[i]), ![UInt8(ascii: "="), UInt8(ascii: ">"), UInt8(ascii: "/")].contains(bytes[i]) {
                i = bytes.index(after: i)
            }
            let name = String(text(bytes, nameStart, i)).lowercased()
            skipSpace(&i, bytes, end)
            guard i < end, bytes[i] == UInt8(ascii: "=") else { continue }
            i = bytes.index(after: i)
            skipSpace(&i, bytes, end)
            var value = ""
            if i < end, bytes[i] == UInt8(ascii: "\"") || bytes[i] == UInt8(ascii: "'") {
                let quote = bytes[i]
                let valueStart = bytes.index(after: i)
                i = valueStart
                while i < end, bytes[i] != quote { i = bytes.index(after: i) }
                value = text(bytes, valueStart, i)
                if i < end { i = bytes.index(after: i) }
            } else {
                let valueStart = i
                while i < end, !isSpace(bytes[i]), bytes[i] != UInt8(ascii: ">") { i = bytes.index(after: i) }
                value = text(bytes, valueStart, i)
            }
            if attributes[name] == nil { attributes[name] = value }
        }
        let key = (attributes["property"] ?? attributes["name"])?.lowercased()
        if let key, wanted.contains(key), head.meta[key] == nil, let content = attributes["content"],
           let cleaned = clean(decodeEntities(content)) {
            head.meta[key] = cleaned
        }
        return i < end ? bytes.index(after: i) : end
    }

    private static func readTitle(from start: String.Index, in bytes: String.UTF8View, end: String.Index, into head: inout Head) -> String.Index {
        var i = start
        while i < end, bytes[i] != UInt8(ascii: ">") { i = bytes.index(after: i) }
        guard i < end else { return end }
        let textStart = bytes.index(after: i)
        i = textStart
        while i < end, !(bytes[i] == UInt8(ascii: "<") && matches("/title", at: bytes.index(after: i), in: bytes, end: end)) {
            i = bytes.index(after: i)
        }
        if head.title == nil, let cleaned = clean(decodeEntities(text(bytes, textStart, i))) { head.title = cleaned }
        return i
    }

    private static func text(_ bytes: String.UTF8View, _ from: String.Index, _ to: String.Index) -> String {
        String(decoding: bytes[from..<to], as: UTF8.self)
    }

    private static func skipSpace(_ i: inout String.Index, _ bytes: String.UTF8View, _ end: String.Index) {
        while i < end, isSpace(bytes[i]) { i = bytes.index(after: i) }
    }

    private static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || (0x09...0x0D).contains(b) }

    private static func lower(_ b: UInt8) -> UInt8 { (0x41...0x5A).contains(b) ? b + 0x20 : b }

    // MARK: - Values -

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    ]

    /// Decodes the fixed entity set; anything else stays as written.
    private static func decodeEntities(_ value: String) -> String {
        guard value.utf8.contains(UInt8(ascii: "&")) else { return value }
        var out = ""
        var rest = Substring(value)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            rest = rest[amp...]
            if let semi = rest.prefix(12).firstIndex(of: ";"), let decoded = decode(String(rest[rest.index(after: rest.startIndex)..<semi])) {
                out += decoded
                rest = rest[rest.index(after: semi)...]
            } else {
                out += "&"
                rest = rest.dropFirst()
            }
        }
        return out + rest
    }

    private static func decode(_ entity: String) -> String? {
        if let named = named[entity] { return named }
        guard entity.hasPrefix("#") else { return nil }
        let digits = entity.dropFirst()
        let hex = digits.hasPrefix("x") || digits.hasPrefix("X")
        guard let code = UInt32(hex ? digits.dropFirst() : digits, radix: hex ? 16 : 10),
              let scalar = Unicode.Scalar(code) else { return nil }
        return String(Character(scalar))
    }

    /// NBSP to space, whitespace runs collapsed, trimmed; nil when nothing is left.
    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let words = value.split(whereSeparator: { $0 == "\u{00A0}" || $0.isWhitespace })
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    private static func imageURL(_ raw: String, relativeTo base: URL) -> URL? {
        guard let url = URL(string: raw, relativeTo: base)?.absoluteURL,
              url.scheme?.lowercased() == "https",
              let host = WebLinks.host(of: url),
              WebLinks.isEligibleHost(host) else { return nil }
        return url
    }
}
