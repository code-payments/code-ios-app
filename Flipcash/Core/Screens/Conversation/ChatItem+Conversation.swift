//
//  ChatItem+Conversation.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore
import FlipcashUI

/// One detector for every remap — `NSDataDetector` compiles its matchers once, and `from(_:)`
/// re-runs on every observable transcript change. `nonisolated(unsafe)` because the mapper runs off
/// the main actor and `LinkDetector` is an immutable wrapper over a thread-safe `NSDataDetector`.
nonisolated(unsafe) private let linkDetector = LinkDetector()

/// Memoizes link detection across remaps: `from(_:)` re-runs on every observable transcript change
/// (typing, receipts, grouping), but a message's link depends only on its immutable text — so a typing
/// tick must not re-scan the whole transcript with `NSDataDetector`. `NSCache` bounds the retained
/// entries, purges under memory pressure, and synchronizes its own access, so the mapper stays
/// non-isolated. Keyed by text, so identical messages share the result.
///
/// Only the detection half is cached. Classification is a closure the caller injects, and it is
/// cheap next to `NSDataDetector`, so the cache holds the spans rather than the card built from
/// them. Nothing about resolution is cached here — a card is identity alone, and the lookup behind
/// it belongs to `LinkCardResolver`, keyed on the entropy.
private final class DetectedLinkBox {
    nonisolated let links: [DetectedLink]
    nonisolated init(_ links: [DetectedLink]) { self.links = links }
}

nonisolated(unsafe) private let linkPreviewCache: NSCache<NSString, DetectedLinkBox> = {
    let cache = NSCache<NSString, DetectedLinkBox>()
    cache.countLimit = 512
    return cache
}()

nonisolated private func detectedLink(in text: String, card: ([DetectedLink]) -> LinkCard?) -> LinkPreview? {
    let key = text as NSString
    let links: [DetectedLink]
    if let cached = linkPreviewCache.object(forKey: key) {
        links = cached.links
    } else {
        links = linkDetector.webLinks(in: text)
        linkPreviewCache.setObject(DetectedLinkBox(links), forKey: key)
    }
    guard !links.isEmpty else { return nil }
    return LinkPreview(links: links, card: card(links))
}

extension ChatItem {

    /// Maps a conversation's messages to display-ready transcript items: resolves sender side,
    /// formats cash amounts, derives the currency flag, inserts a date separator before the first
    /// message, whenever a gap longer than `gap` opens and at every change of day, and computes
    /// same-sender grouping the way the transcript does. Pure — `cashBranding` supplies the token
    /// name + launchpad icon so this stays testable; it defaults to plain "Cash" (USDF), and the
    /// screen injects bonded-mint branding from `Session`.
    nonisolated static func from(
        _ messages: [ConversationMessage],
        selfUserID: UserID,
        // How long a pause has to be before it heads the next message with its own separator and
        // ends the run above it. Android's `SeparatorConfig.Continuous` gap, so a pause of minutes
        // keeps one exchange together on both platforms instead of cutting it into single bubbles.
        gap: TimeInterval = 3 * 60 * 60,
        counterpartRead: (pointer: MessageID, date: Date?)? = nil,
        suppressReceiptFor: String? = nil,
        cashBranding: (ExchangedFiat) -> (token: String, iconURL: URL?) = { _ in ("Cash", nil) },
        deletedPresentation: DeletedMessagePresentation = .hidden,
        capabilities: (ConversationMessage) -> Set<MessageCapability> = { _ in [] },
        counterpartName: String = "",
        quotedMessage: (MessageID) -> ConversationMessage? = { _ in nil },
        author: (ConversationMessage) -> ChatAuthor? = { _ in nil },
        namesAuthors: Bool = false,
        /// The card, if any, for a message's detected links. Injected like the other collaborators
        /// so the mapper stays pure; the screen supplies classification and nothing else, and it
        /// defaults to no card. Takes the detected links rather than the text so the detector runs
        /// once per message, here.
        linkCard: ([DetectedLink]) -> LinkCard? = { _ in nil },
        /// Where the viewer's unread messages began at open; the divider heads the first message
        /// after it that someone else sent.
        unreadBoundary: UnreadBoundary = .none
    ) -> [ChatItem] {
        // Tombstoned (deleted) messages are retained in the store for gapless ordering. Under
        // `.hidden` they are dropped up front so they never skew a date separator, group an adjacent
        // bubble to an invisible row, or steal the "Delivered"/"Read" receipt anchor below.
        let messages: [ConversationMessage] = switch deletedPresentation {
        case .hidden:      messages.filter { !$0.isDeleted }
        case .placeholder: messages
        }

        // "Delivered"/"Read" rides the latest *confirmed* self message, so an in-flight or failed send
        // trailing it doesn't strip the receipt off the last delivered bubble. A sending row shows
        // nothing; a failed row shows its own "Not Delivered" line (each independently retryable).
        // A tombstone has nothing to acknowledge, so it must not take the receipt from the last row
        // that does — it is skipped here even when it is the newest self message.
        let latestSentFromSelfID = messages.last {
            $0.isFromSelf(selfUserID) && $0.status == .sent && !$0.isDeleted
        }?.stableID
        // A separator heads `message` when the pause before `earlier` ran longer than the gap, or
        // when the two fall on different days — the second is what keeps a late-night exchange from
        // reading as one run across midnight, which the gap alone would let through.
        let calendar = Calendar.current
        func separates(_ message: ConversationMessage, from earlier: ConversationMessage) -> Bool {
            message.date.timeIntervalSince(earlier.date) > gap
                || !calendar.isDate(message.date, inSameDayAs: earlier.date)
        }

        // The unread divider heads `message` when the read-through falls between it and `earlier`.
        // Like a separator it ends the run above it: a bubble must not join one across the divider.
        func divides(_ message: ConversationMessage, from earlier: ConversationMessage) -> Bool {
            unreadBoundary.dividerBetween(newer: message, older: earlier, selfUserID: selfUserID)
        }

        // What breaks the bubble run: a text body of one to three emoji, on a row that is not a
        // reply — the quote panel lives inside the bubble and has no standalone layout. Narrower
        // than `ChatMessage.rendersAsLargeEmoji`, which also has a link row to rule out.
        func isEmojiOnlyBody(_ message: ConversationMessage) -> Bool {
            switch message.content {
            case .text(let text): EmojiOnlyDetector.isEmojiOnly(text)
            case .cash, .deleted, .encrypted: false
            }
        }
        func rendersBare(_ message: ConversationMessage) -> Bool {
            message.repliedTo == nil && isEmojiOnlyBody(message)
        }

        // Each message's rows, worked out up front because a neighbour's first and last rows decide
        // whether a bubble here joins it. One row for most messages; a message with a link card is
        // split around it.
        let layouts = messages.map { message in
            switch message.content {
            case .text(let text): Self.rows(for: text, preview: detectedLink(in: text, card: linkCard))
            case .cash, .deleted, .encrypted: [RowLayout(part: nil, text: nil, preview: nil)]
            }
        }
        var items: [ChatItem] = []
        for (index, message) in messages.enumerated() {
            let isFromSelf = message.isFromSelf(selfUserID)
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil

            // A separator opens the transcript and breaks any run longer than the gap.
            let showsSeparator = previous.map { separates(message, from: $0) } ?? true
            if showsSeparator {
                items.append(.dateSeparator(id: "sep-\(message.stableID)", text: message.date.formattedChatSeparator()))
            }
            // Below the date when both fall at one gap: the reader sees the day, then what is new.
            let showsDivider = previous.map { divides(message, from: $0) } ?? false
            if showsDivider, let count = unreadBoundary.count {
                items.append(.unreadDivider(count: count))
            }

            // Grouped by author, not by side: in a group chat two different people's messages sit on
            // the same edge, and comparing sides would merge them into one run with its facing
            // corners flattened — one column of bubbles attributed to whoever the run started with.
            // `senderID` is nil only for a legacy row with no sender, and two of those group the way
            // they always did.
            //
            // A run ends exactly where a separator starts, rather than on a window of its own: the
            // separator is already the heading of what follows it, so a second, shorter threshold
            // would flatten runs the transcript still draws as continuous.
            let groupedAbove = previous.map {
                $0.senderID == message.senderID && !showsSeparator && !showsDivider
            } ?? false
            let groupedBelow = next.map {
                $0.senderID == message.senderID && !separates($0, from: message) && !divides($0, from: message)
            } ?? false

            // The bubble run, which is not the author run. A bubble stacked above a bare emoji would
            // otherwise flatten its inner corner to `BubbleBackgroundView.groupedRadius`
            // and take the tight row gap, pointing at a bubble that is not there — while the name and
            // the gutter face stay where they are.
            // A card row is no break: it is cut to the same per-corner shape a bubble is, so it joins
            // the bubbles around it like one.
            let joinsBubbleAbove = groupedAbove && !rendersBare(message) && !(previous.map(rendersBare) ?? false)
            let joinsBubbleBelow = groupedBelow && !rendersBare(message) && !(next.map(rendersBare) ?? false)

            let content: ChatMessage.Content
            switch message.content {
            case .text(let text):
                content = .text(text)
            case .cash(let fiat):
                let branding = cashBranding(fiat)
                content = .cash(ChatCashContent(
                    amount: fiat.nativeAmount.formatted(),
                    token: branding.token,
                    flagImageName: flagImageName(for: fiat),
                    iconURL: branding.iconURL,
                    isTip: message.cashAction == .tipped
                ))
            case .deleted(let deletion):
                content = .deleted(
                    deletion.deletedBy == selfUserID
                        ? "You deleted this message"
                        : "This message was deleted"
                )
            case .encrypted:
                // Decryption isn't implemented on this client -- a cross-platform parity hotspot --
                // so an encrypted message renders as the same non-interactive placeholder bubble a
                // tombstone does, with copy matching Android's unsupported-content bubble.
                content = .deleted(ChatMessage.unsupportedContentCopy)
            }

            // The status line rides on the bubble itself (not a separate row, so a send is a clean
            // insert). All of its copy is produced here, in one layer; the cell only styles it
            // (resting vs. red + tappable) off `isFailed`.
            let receipt: ChatReceipt?
            switch message.status {
            case .sent:
                // "Delivered"/"Read" rides only the latest confirmed self message — preserved even when
                // a later send is in flight or failed, and held back while the row is still settling in.
                // `latestSentFromSelfID` is already a self+sent row, so matching it implies both.
                receipt = message.stableID == latestSentFromSelfID && message.stableID != suppressReceiptFor
                    ? Self.receipt(for: message.id, counterpartRead: counterpartRead)
                    : nil
            case .sending:
                // No status line while in flight — the bubble sits there until it resolves to
                // "Delivered" or the failed state.
                receipt = nil
            case .failed:
                receipt = .failed("Not Delivered. Tap to retry")
            }

            // Resolved here rather than in the view so all three states — found, never fetched,
            // deleted — are decided by one pure function and testable without a database.
            let quote = message.repliedTo.map { repliedTo in
                Self.quote(
                    resolving: quotedMessage(repliedTo),
                    selfUserID: selfUserID,
                    counterpartName: counterpartName,
                    cashBranding: cashBranding,
                    author: author
                )
            }

            // Only a confirmed row has an id the READ pointer can move to.
            let serverID: MessageID? = switch message.status {
            case .sent:              message.id
            case .sending, .failed:  nil
            }

            // A split message reads as one: the quote heads its first row, the receipt and the
            // "Edited" marker close its last, and every row between holds the author run and offers
            // the whole message's menu.
            let rows = layouts[index]
            for (position, row) in rows.enumerated() {
                let isFirst = position == 0
                let isLast = position == rows.count - 1
                let part = row.part.map {
                    ChatMessagePart(messageID: message.stableID, kind: $0, messageText: row.messageText ?? "")
                }
                items.append(.message(ChatMessage(
                    id: part?.rowID ?? message.stableID,
                    serverID: serverID,
                    content: row.text.map(ChatMessage.Content.text) ?? content,
                    sender: isFromSelf ? .me : .other,
                    isContinuationFromPrevious: isFirst ? groupedAbove : true,
                    isContinuedByNext: isLast ? groupedBelow : true,
                    // The rows of a split message are one run: text, card and text join each other.
                    joinsBubbleAbove: isFirst ? joinsBubbleAbove : true,
                    joinsBubbleBelow: isLast ? joinsBubbleBelow : true,
                    isEmojiOnly: part == nil && isEmojiOnlyBody(message),
                    receipt: isLast ? receipt : nil,
                    linkPreview: row.preview,
                    isEdited: isLast && message.lastEditedTs != nil && !message.isDeleted,
                    actions: orderedActions(capabilities(message)),
                    quote: isFirst ? quote : nil,
                    // The viewer's own rows are never attributed: the trailing edge already says who
                    // wrote them, and a name and avatar over them would read as a second speaker.
                    author: isFromSelf ? nil : author(message),
                    // Carried on every row of a group transcript, not just the ones that resolved an
                    // author, so the gutter the faces sit in is held open for all of them and the
                    // incoming bubbles share one leading edge.
                    isAttributedTranscript: namesAuthors,
                    part: part
                )))
            }
        }
        return items
    }

    /// The quoted original, for each of the three states it can be in. A message the local database
    /// has never seen and a tombstone both render as unavailable and both refuse the jump — the
    /// first because there is no row to land on, the second because `.hidden` filters the tombstone
    /// out of the transcript entirely.
    nonisolated private static func quote(
        resolving original: ConversationMessage?,
        selfUserID: UserID,
        counterpartName: String,
        cashBranding: (ExchangedFiat) -> (token: String, iconURL: URL?),
        author: (ConversationMessage) -> ChatAuthor?
    ) -> ChatQuote {
        guard let original else {
            return ChatQuote(
                stableID: nil,
                authorName: "",
                snippet: ChatQuote.unavailableSnippet,
                kind: .unavailable
            )
        }
        // A group quote names the real writer; `counterpartName` is the DM's single other party and
        // would attribute every quoted message in a group to whoever the chat is titled after.
        let authorName = original.isFromSelf(selfUserID)
            ? "You"
            : (author(original).map { $0.name.isEmpty ? counterpartName : $0.name } ?? counterpartName)
        switch original.content {
        case .text(let text):
            return ChatQuote(
                stableID: original.stableID,
                authorName: authorName,
                snippet: ChatQuote.snippet(forText: text),
                kind: .text,
                authorID: original.senderID
            )
        case .cash(let fiat):
            // Same branding the card carries, so the quote of a payment reads as that payment. The
            // launchpad icon is deliberately left out: it is a remote fetch, and the flag already
            // keys the currency at this size.
            return ChatQuote(
                stableID: original.stableID,
                authorName: authorName,
                snippet: fiat.nativeAmount.formatted(),
                kind: .cash(token: cashBranding(fiat).token, flagImageName: flagImageName(for: fiat)),
                authorID: original.senderID
            )
        case .deleted:
            return ChatQuote(
                stableID: nil,
                authorName: authorName,
                snippet: ChatQuote.deletedSnippet,
                kind: .unavailable,
                authorID: original.senderID
            )
        case .encrypted:
            // No plaintext to preview -- same unavailable treatment as a quote whose original the
            // local database never saw.
            return ChatQuote(
                stableID: nil,
                authorName: authorName,
                snippet: ChatQuote.unavailableSnippet,
                kind: .unavailable,
                authorID: original.senderID
            )
        }
    }

    /// The currency's flag asset: a region flag where the currency has one, else the ticker, which
    /// is how the crypto flags are named. One derivation for the card and the quote so a payment
    /// keys the same way wherever it is drawn.
    nonisolated static func flagImageName(for fiat: ExchangedFiat) -> String {
        let currency = fiat.nativeAmount.currency
        return currency.region?.rawValue ?? currency.rawValue.uppercased()
    }

    /// One row a message draws: the whole message, or one part of a message split around its card.
    nonisolated struct RowLayout {
        /// Nil for a row that is the whole message.
        let part: ChatMessagePart.Kind?
        /// The row's text, or nil to draw the message's own content.
        let text: String?
        let preview: LinkPreview?
        /// The whole message's text, for a split row's Copy.
        var messageText: String? = nil
    }

    /// The rows a text message draws, in the order the sender wrote them: the text before the
    /// carded link, the card, and the text after it, each skipped when it would hold nothing but
    /// whitespace. A message with no card is one row, as it always was.
    ///
    /// The whitespace between the link and the text on either side goes with the link — it was the
    /// gap around a word that now has a row of its own. Every other link stays in whichever text row
    /// it fell in, underlined, with its span moved into that row's frame.
    ///
    /// A card whose span does not fit the text — a stale preview — is dropped rather than split, and
    /// the message renders as text with its links underlined.
    nonisolated static func rows(for text: String, preview: LinkPreview?) -> [RowLayout] {
        guard let preview, let card = preview.card else {
            return [RowLayout(part: nil, text: nil, preview: preview)]
        }
        let body = text as NSString
        let link = card.range
        guard link.location >= 0, link.length > 0, NSMaxRange(link) <= body.length else {
            return [RowLayout(part: nil, text: nil, preview: LinkPreview(links: preview.links, card: nil))]
        }

        func isGap(_ index: Int) -> Bool {
            guard let scalar = Unicode.Scalar(body.character(at: index)) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        var leadingEnd = link.location
        while leadingEnd > 0, isGap(leadingEnd - 1) { leadingEnd -= 1 }
        var trailingStart = NSMaxRange(link)
        while trailingStart < body.length, isGap(trailingStart) { trailingStart += 1 }

        // The links inside `span`, re-based to its start. A row with no link keeps no preview, so it
        // takes the plain text cell.
        func textRow(_ kind: ChatMessagePart.Kind, _ span: NSRange) -> RowLayout? {
            guard span.length > 0 else { return nil }
            let links = preview.links.compactMap { detected -> DetectedLink? in
                guard detected.location >= span.location,
                      NSMaxRange(detected.range) <= NSMaxRange(span) else { return nil }
                return DetectedLink(
                    range: NSRange(location: detected.location - span.location, length: detected.length),
                    url: detected.url
                )
            }
            return RowLayout(
                part: kind,
                text: body.substring(with: span),
                preview: links.isEmpty ? nil : LinkPreview(links: links),
                messageText: text
            )
        }

        let cardSpan = NSRange(location: 0, length: link.length)
        let cardLink = preview.links.first { $0.range == link }
            .map { DetectedLink(range: cardSpan, url: $0.url) }
            ?? DetectedLink(range: cardSpan, url: card.url)
        let cardRow = RowLayout(
            part: .card,
            text: body.substring(with: link),
            preview: LinkPreview(links: [cardLink], card: card.relocated(to: cardSpan)),
            messageText: text
        )

        return [
            textRow(.leadingText, NSRange(location: 0, length: leadingEnd)),
            cardRow,
            textRow(.trailingText, NSRange(location: trailingStart, length: body.length - trailingStart)),
        ].compactMap { $0 }
    }

    /// Menu order is fixed here, not at the call site — a `Set` has no order, and the context menu
    /// must not shuffle its rows between renders of the same message.
    ///
    /// Report goes last: it is the rarest row and the only one that never appears on your own
    /// message, so the menu reads "yours ends with delete, theirs ends with report".
    nonisolated private static func orderedActions(_ capabilities: Set<MessageCapability>) -> [MessageCapability] {
        [.copy, .reply, .edit, .delete, .report].filter(capabilities.contains)
    }

    /// "Read 3:42 PM" / "Read Yesterday" / "Read Monday" / "Read Tue, Jun 17" once the counterpart's
    /// read pointer reaches the message, else "Delivered".
    nonisolated private static func receipt(for messageID: MessageID, counterpartRead: (pointer: MessageID, date: Date?)?) -> ChatReceipt {
        guard let read = counterpartRead, read.pointer >= messageID else { return .delivered }
        guard let date = read.date else { return .read(time: nil) }
        return .read(time: date.formattedRelatively(useTimeForToday: true))
    }
}
