//
//  ChatRequestEvent.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Something that happened to a payment request, drawn as one centred line in the transcript: a
/// share paid in Flipcash, a share the creator marked paid, or the request closed.
public struct ChatRequestEvent: Hashable, Sendable, Codable {

    public enum Kind: String, Hashable, Sendable, Codable {
        /// One or more members paid their share; backed by `.cash` messages.
        case sharePayment
        /// The creator marked one or more shares paid; built from the stored request.
        case markedPaid
        /// The creator closed the request; built from the stored request.
        case closed
    }

    /// A piece of the caption.
    public struct Span: Hashable, Sendable, Codable {
        public var text: String
        /// Drawn semibold, as a system row draws a user's name.
        public var isEmphasized: Bool
        /// A member's display name.
        public var isName: Bool

        public init(_ text: String, isEmphasized: Bool = false, isName: Bool = false) {
            self.text = text
            self.isEmphasized = isEmphasized
            self.isName = isName
        }

        /// A member's display name.
        public static func name(_ text: String) -> Span { Span(text, isEmphasized: true, isName: true) }
        /// "You" or "you", standing in for the viewer's name.
        public static func viewer(_ text: String) -> Span { Span(text, isEmphasized: true) }
    }

    public let id: String
    public let kind: Kind
    /// Who did what, without the amount or the title: "Jordan paid Alex".
    public let caption: [Span]
    /// The amount paid, formatted for the viewer; `nil` for a row where no money moved.
    public let amount: String?
    /// The request's title; `nil` while the request can't be shown.
    public let title: String?
    /// The request's paid fraction as of this event; `nil` draws no ring.
    public let ringFraction: Double?
    /// The request Request details opens for; `nil` leaves the row inert.
    public let requestID: Data?
    /// The newest message this row draws, which the READ pointer moves past; `nil` for a row with
    /// no message behind it.
    public let serverID: MessageID?
    /// The stable ids of the messages this row draws, oldest first; empty for a row with none.
    public let messageIDs: [String]

    public init(
        id: String,
        kind: Kind,
        caption: [Span],
        amount: String? = nil,
        title: String? = nil,
        ringFraction: Double? = nil,
        requestID: Data? = nil,
        serverID: MessageID? = nil,
        messageIDs: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.caption = caption
        self.amount = amount
        self.title = title
        self.ringFraction = ringFraction
        self.requestID = requestID
        self.serverID = serverID
        self.messageIDs = messageIDs
    }

    /// What joins the title to the text before it: a closed row reads "Alex closed Tahoe cabin",
    /// the others "… · Tahoe cabin".
    public var titleSeparator: String {
        switch kind {
        case .sharePayment, .markedPaid: " · "
        case .closed:                    " "
        }
    }

    /// The whole row as one string, for VoiceOver.
    public var spokenText: String {
        var text = caption.map(\.text).joined()
        if let amount { text += " \(amount)" }
        if let title { text += titleSeparator + title }
        return text
    }
}

// MARK: - Fit

extension ChatRequestEvent {

    /// Whether the row takes two lines, the caption and amount over the title and ring. A row that
    /// fits `maxWidth` on one line stays on one; nothing in it is ever shortened.
    ///
    /// `width` measures the row on one line, with the title and its ring when `includesTitle`.
    public func wraps(maxWidth: Double, width: (_ includesTitle: Bool) -> Double) -> Bool {
        title != nil && width(true) > maxWidth
    }

    /// Breaks words into lines of at most `maxWidth`, breaking only between words, and returns each
    /// line's range of word indices. `widths` are the words' own widths and `gap` the space between
    /// neighbours. `trailing` is room the last line keeps after its last word (the ring and its
    /// gap): the last word moves to a line of its own when the line couldn't hold both. A word wider
    /// than `maxWidth` takes a line to itself.
    public static func wrapLines(widths: [Double], gap: Double, maxWidth: Double, trailing: Double = 0) -> [Range<Int>] {
        guard !widths.isEmpty else { return [] }
        var lines: [Range<Int>] = []
        var start = 0
        var used = widths[0]
        for index in 1..<widths.count {
            if used + gap + widths[index] > maxWidth {
                lines.append(start..<index)
                start = index
                used = widths[index]
            } else {
                used += gap + widths[index]
            }
        }
        lines.append(start..<widths.count)

        if trailing > 0, let last = lines.last, last.count > 1, used + trailing > maxWidth {
            lines[lines.count - 1] = last.lowerBound..<(last.upperBound - 1)
            lines.append((last.upperBound - 1)..<last.upperBound)
        }
        return lines
    }
}
