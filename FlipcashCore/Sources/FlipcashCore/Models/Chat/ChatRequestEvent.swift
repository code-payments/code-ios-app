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
        /// A member's display name, which the fit rule may shorten.
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

    /// How a row's text is cut to fit its width.
    public struct Fit: Hashable, Sendable {
        /// The caption, with names shortened where the row needed the room.
        public var caption: [Span]
        /// The title as drawn. On a wrapped row it is the whole title, which the second line
        /// truncates at its end.
        public var title: String?
        /// Whether the title, and the ring with it, moves to a second line.
        public var wraps: Bool
    }

    /// The fewest characters a shortened title keeps, ellipsis included.
    public static let shortestTitle = 8
    /// The fewest characters a shortened name keeps, ellipsis included.
    public static let shortestName = 6

    /// Cuts the row to `maxWidth`: the title shortens first, then each name, and only then the title
    /// wraps to a second line. The amount is never cut.
    ///
    /// `width` measures one line holding the given caption, the amount, and the title with its
    /// ring when a title is passed.
    public func fit(maxWidth: Double, width: (_ caption: [Span], _ title: String?) -> Double) -> Fit {
        if width(caption, title) <= maxWidth {
            return Fit(caption: caption, title: title, wraps: false)
        }

        var shortTitle = title
        if let title {
            for candidate in Self.shortenings(of: title, floor: Self.shortestTitle) {
                shortTitle = candidate
                if width(caption, candidate) <= maxWidth {
                    return Fit(caption: caption, title: candidate, wraps: false)
                }
            }
        }

        let shortNames = Self.shorteningNames(in: caption) { width($0, shortTitle) <= maxWidth }
        if shortNames.fits || title == nil {
            return Fit(caption: shortNames.caption, title: shortTitle, wraps: false)
        }

        // The first line holds the caption and amount alone, so the names get back what fits there.
        let firstLine = Self.shorteningNames(in: caption) { width($0, nil) <= maxWidth }
        return Fit(caption: firstLine.caption, title: title, wraps: true)
    }

    /// `text` cut one character shorter at a time, each ending in an ellipsis, down to `floor`
    /// characters; empty when `text` is already that short.
    static func shortenings(of text: String, floor: Int) -> [String] {
        let characters = Array(text)
        guard characters.count > floor else { return [] }
        return stride(from: characters.count - 2, through: floor - 1, by: -1).map { kept in
            String(characters.prefix(kept)).trimmingCharacters(in: .whitespaces) + "…"
        }
    }

    /// Shortens the longest name a character at a time until `fits` passes or every name is down to
    /// ``shortestName``.
    private static func shorteningNames(in caption: [Span], until fits: ([Span]) -> Bool) -> (caption: [Span], fits: Bool) {
        var current = caption
        if fits(current) { return (current, true) }
        // Each name's remaining cuts, shortest last.
        var remaining: [Int: [String]] = [:]
        for (index, span) in caption.enumerated() where span.isName {
            remaining[index] = shortenings(of: span.text, floor: shortestName)
        }
        while true {
            let longest = remaining
                .filter { !$0.value.isEmpty }
                .max { lhs, rhs in
                    let left = current[lhs.key].text.count, right = current[rhs.key].text.count
                    return left == right ? lhs.key > rhs.key : left < right
                }
            guard let longest else { return (current, false) }
            current[longest.key].text = remaining[longest.key]!.removeFirst()
            if fits(current) { return (current, true) }
        }
    }
}
