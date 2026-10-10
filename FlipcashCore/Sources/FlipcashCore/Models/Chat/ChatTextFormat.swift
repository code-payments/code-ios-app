//
//  ChatTextFormat.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// One style over a row's display text. Offsets are UTF-16, as `NSRange`.
public struct ChatTextSpan: Hashable, Sendable, Codable {

    public enum Style: String, Hashable, Sendable, Codable {
        case bold, italic, strike, code, codeBlock, quote, bullet, numbered
    }

    public let style: Style
    public let location: Int
    public let length: Int

    public var range: NSRange { NSRange(location: location, length: length) }

    public init(style: Style, range: NSRange) {
        self.style = style
        self.location = range.location
        self.length = range.length
    }

    init(_ span: TextFormat.Span) {
        let style: Style = switch span {
        case .bold: .bold
        case .italic: .italic
        case .strike: .strike
        case .code: .code
        case .codeBlock: .codeBlock
        case .quote: .quote
        case .bullet: .bullet
        case .numbered: .numbered
        }
        self.init(style: style, range: span.range)
    }
}

/// What the parser made of a text row, kept beside the row so a copy can still hand back the raw
/// markup the sender typed.
public struct ChatTextFormat: Hashable, Sendable, Codable {

    /// The text as sent. `.text` on the row holds the display text instead.
    public let raw: String
    public let spans: [ChatTextSpan]

    public init(raw: String, spans: [ChatTextSpan]) {
        self.raw = raw
        self.spans = spans
    }

    /// Whether anything needs the text view: a block style draws a bar or an indent, which the
    /// plain label cannot.
    public var needsTextView: Bool {
        spans.contains { span in
            switch span.style {
            case .quote, .bullet, .numbered: true
            case .bold, .italic, .strike, .code, .codeBlock: false
            }
        }
    }
}

/// A text row after parsing: the words to draw, their styles, and the link preview moved onto them.
public struct FormattedChatText: Hashable, Sendable {
    public let display: String
    public let format: ChatTextFormat?
    public let preview: LinkPreview?
}

/// Runs the shared parser over a text row and moves the row's link preview onto the display text.
public enum ChatTextFormatter {

    /// `preview` is what detection found in `raw`. Its links and mentions go to the parser as
    /// protected ranges, and come back at their display offsets. A masked link comes back as a link
    /// over its text, pointing at its target.
    ///
    /// If the parser's ranges do not line up with the preview's, which means the two disagree about
    /// what a masked link is, the row is left as typed rather than guessed at.
    public static func format(_ raw: String, preview: LinkPreview?) -> FormattedChatText {
        let links = preview?.links ?? []
        let mentions = preview?.mentions ?? []
        let parsed = TextFormat.parse(
            raw,
            ranges: links.map { TextFormat.ProtectedRange(range: $0.range, kind: .link) }
                + mentions.map { TextFormat.ProtectedRange(range: $0.range, kind: .mention) }
        )
        guard parsed.display != raw || !parsed.spans.isEmpty else {
            return FormattedChatText(display: raw, format: nil, preview: preview)
        }

        // The links the parser kept as themselves: every detected link except the target of a
        // masked link, which it consumed. They keep their order, so they pair off one to one.
        let rawText = raw as NSString
        let bareLinks = links.filter { !isMaskTarget($0.range, in: rawText) }
        let bareRanges = parsed.displayRanges.filter { $0.kind == .link && $0.target == nil }
        let mentionRanges = parsed.displayRanges.filter { $0.kind == .mention }
        let maskedRanges = parsed.displayRanges.filter { $0.kind == .link && $0.target != nil }
        guard bareLinks.count == bareRanges.count, mentions.count == mentionRanges.count else {
            return FormattedChatText(display: raw, format: nil, preview: preview)
        }

        let display = parsed.display as NSString
        var movedLinks: [DetectedLink] = zip(bareLinks, bareRanges).map { detected, shown in
            DetectedLink(range: shown.range, url: detected.url)
        }
        // A masked link whose address would not parse has no target: its text must not be opened
        // as an address, so it is drawn as plain text.
        movedLinks += maskedRanges.compactMap { shown in
            shown.target.map {
                DetectedLink(range: shown.range, url: $0, maskedLabel: display.substring(with: shown.range))
            }
        }
        movedLinks.sort { $0.location < $1.location }
        let movedMentions = zip(mentions, mentionRanges).map { detected, shown in
            DetectedMention(range: shown.range, username: detected.username)
        }

        var card = preview?.card
        if let current = card, let index = bareLinks.firstIndex(where: { $0.range == current.range }) {
            card = current.relocated(to: bareRanges[index].range)
        }

        let moved: LinkPreview? = movedLinks.isEmpty && movedMentions.isEmpty && card == nil
            ? nil
            : LinkPreview(links: movedLinks, card: card, mentions: movedMentions)
        let spans = parsed.spans.map(ChatTextSpan.init)
        return FormattedChatText(
            display: parsed.display,
            format: ChatTextFormat(raw: raw, spans: spans),
            preview: moved
        )
    }

    /// `raw` with its markers taken out and nothing else: the words for a reply quote, a chat list
    /// preview, a notification or a Spotlight entry, none of which draw styles. Detects links and
    /// mentions itself, since a marker inside one is not a marker.
    public static func displayText(of raw: String) -> String {
        format(detecting: raw).display
    }

    /// ``format(_:preview:)`` for a caller that has not run detection: finds the links and mentions
    /// in `raw` first.
    public static func format(detecting raw: String) -> FormattedChatText {
        guard raw.contains(where: markerCharacters.contains) else {
            return FormattedChatText(display: raw, format: nil, preview: nil)
        }
        let links = detector.webLinks(in: raw)
        let mentions = MentionDetector.mentions(in: raw, excluding: links)
        let preview = links.isEmpty && mentions.isEmpty ? nil : LinkPreview(links: links, mentions: mentions)
        return format(raw, preview: preview)
    }

    /// Every character the parser reads as markup, `.` for `1. `. A text with none is its own display.
    private static let markerCharacters: Set<Character> = ["*", "_", "~", "`", ">", "-", "[", "\\", "."]

    private nonisolated(unsafe) static let detector = LinkDetector()

    /// Whether the link at `range` is the address inside `[text](address)`: the construct the
    /// parser consumes. Such a link is never a card, since the words around it are the sender's
    /// label and not a message about the link.
    public static func isMaskTarget(_ range: NSRange, in text: NSString) -> Bool {
        guard range.location >= 2, NSMaxRange(range) < text.length else { return false }
        return text.substring(with: NSRange(location: range.location - 2, length: 2)) == "]("
            && text.character(at: NSMaxRange(range)) == 0x29 // ")"
    }
}
