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
    nonisolated let mentions: [DetectedMention]
    nonisolated init(_ links: [DetectedLink], _ mentions: [DetectedMention]) {
        self.links = links
        self.mentions = mentions
    }
}

nonisolated(unsafe) private let linkPreviewCache: NSCache<NSString, DetectedLinkBox> = {
    let cache = NSCache<NSString, DetectedLinkBox>()
    cache.countLimit = 512
    return cache
}()

nonisolated private func detectedLink(in text: String, card: ([DetectedLink]) -> LinkCard?) -> LinkPreview? {
    let key = text as NSString
    let links: [DetectedLink]
    let mentions: [DetectedMention]
    if let cached = linkPreviewCache.object(forKey: key) {
        links = cached.links
        mentions = cached.mentions
    } else {
        links = linkDetector.webLinks(in: text)
        mentions = MentionDetector.mentions(in: text, excluding: links)
        linkPreviewCache.setObject(DetectedLinkBox(links, mentions), forKey: key)
    }
    guard !links.isEmpty || !mentions.isEmpty else { return nil }
    return LinkPreview(links: links, card: card(links), mentions: mentions)
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
        /// Whether the viewer may add or remove a reaction — false for someone previewing a group
        /// they have not joined, or who fails a reaction-blocking speaker rule (see `ChatMessage.canReact`).
        canReact: Bool = true,
        /// The card, if any, for a message's detected links. Injected like the other collaborators
        /// so the mapper stays pure; the screen supplies classification and nothing else, and it
        /// defaults to no card. Takes the detected links rather than the text so the detector runs
        /// once per message, here.
        linkCard: ([DetectedLink]) -> LinkCard? = { _ in nil },
        /// Where the viewer's unread messages began at open; the divider heads the first message
        /// after it that someone else sent.
        unreadBoundary: UnreadBoundary = .none,
        /// Whether `messages` starts at the chat's first message. The encryption marker heads an
        /// all-encrypted transcript only then, since older history may still be plaintext.
        headsHistory: Bool = true
    ) -> [ChatItem] {
        // Tombstoned (deleted) messages are retained in the store for gapless ordering. Under
        // `.hidden` they are dropped up front so they never skew a date separator, group an adjacent
        // bubble to an invisible row, or steal the "Delivered"/"Read" receipt anchor below.
        // A message still waiting on the peer's key is left out until it decrypts.
        let messages: [ConversationMessage] = switch deletedPresentation {
        case .hidden:      messages.filter { !$0.isDeleted && !$0.isAwaitingDecryption }
        case .placeholder: messages.filter { !$0.isAwaitingDecryption }
        }

        // The marker goes where the ciphertext starts: above the first encrypted message with
        // plaintext before it, or at the head of a history that is encrypted from the start.
        let markerIndex = messages.firstIndex(where: \.isEncrypted).flatMap { index in
            index > 0 || headsHistory ? index : nil
        }

        // "Delivered"/"Read" rides the latest *confirmed* self message, so an in-flight or failed send
        // trailing it doesn't strip the receipt off the last delivered bubble. A sending row shows
        // nothing; a failed row shows its own "Not Delivered" line (each independently retryable).
        // A tombstone has nothing to acknowledge, so it must not take the receipt from the last row
        // that does — it is skipped here even when it is the newest self message.
        //
        // A confirmed send that is still settling (`suppressReceiptFor`) doesn't take it yet either:
        // the row above keeps its line until the settle gate releases, or until confirmation if that
        // lands later, and then the line moves to the new row in one diff — the old line leaves as
        // the new one arrives, rather than dropping at confirmation and reappearing a beat later.
        let latestSentFromSelfID = messages.last {
            $0.isFromSelf(selfUserID) && $0.status == .sent && !$0.isDeleted && $0.stableID != suppressReceiptFor
        }?.stableID
        // "Read" stays on the newest self message the counterpart has read, iMessage-style, when a
        // newer one has only been delivered: the two lines sit under their own bubbles rather than
        // one line claiming the whole run is read. When the newest is read too, they're the same row.
        let latestReadFromSelfID: String? = counterpartRead.flatMap { read in
            messages.last {
                $0.isFromSelf(selfUserID) && $0.status == .sent && !$0.isDeleted && $0.id <= read.pointer
            }?.stableID
        }
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
            case .cash, .deleted, .encrypted, .widget: false
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
            case .cash, .deleted, .encrypted, .widget: [RowLayout(part: nil, text: nil, preview: nil)]
            }
        }
        // A status line under a message sits between it and the next bubble, so it ends the bubble
        // run there too: the two keep their round corners and the normal gap until the line moves
        // on, and then they join.
        func carriesReceipt(_ index: Int) -> Bool {
            let message = messages[index]
            switch message.status {
            case .sent:
                return message.stableID == latestSentFromSelfID
                    || (counterpartRead != nil && message.stableID == latestReadFromSelfID)
            case .failed:
                return true
            case .sending:
                return false
            }
        }

        var items: [ChatItem] = []
        for (index, message) in messages.enumerated() {
            let isFromSelf = message.isFromSelf(selfUserID)
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil

            // A separator opens the transcript and breaks any run longer than the gap.
            let showsSeparator = previous.map { separates(message, from: $0) } ?? true
            let showsMarker = index == markerIndex
            if showsMarker {
                items.append(.encryptionMarker)
            }
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
                $0.senderID == message.senderID && !showsSeparator && !showsDivider && !showsMarker
            } ?? false
            let groupedBelow = next.map {
                $0.senderID == message.senderID && !separates($0, from: message) && !divides($0, from: message)
                    && index + 1 != markerIndex
            } ?? false

            // The bubble run, which is not the author run. A bubble stacked above a bare emoji would
            // otherwise flatten its inner corner to `BubbleBackgroundView.groupedRadius`
            // and take the tight row gap, pointing at a bubble that is not there — while the name and
            // the gutter face stay where they are.
            // A card row is no break: it is cut to the same per-corner shape a bubble is, so it joins
            // the bubbles around it like one. A receipt line between two bubbles is one.
            let joinsBubbleAbove = groupedAbove && !rendersBare(message) && !(previous.map(rendersBare) ?? false)
                && !(index > 0 && carriesReceipt(index - 1))
            let joinsBubbleBelow = groupedBelow && !rendersBare(message) && !(next.map(rendersBare) ?? false)
                && !carriesReceipt(index)

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
            case .widget(.shareProfile(let share)):
                content = .shareProfile(LinkCard.User(profileOf: share.username))
            case .widget(.unrecognized):
                // A widget variant this build doesn't draw; a newer one will.
                content = .unavailable(.updateApp)
            case .encrypted:
                // Still encrypted here means decryption failed; the awaiting ones were dropped above.
                content = .unavailable(.decryptFailure(
                    message.decryptFailure,
                    isFromSelf: isFromSelf,
                    senderName: counterpartName
                ))
            }

            // The status line rides on the bubble itself (not a separate row, so a send is a clean
            // insert). All of its copy is produced here, in one layer; the cell only styles it
            // (resting vs. red + tappable) off `isFailed`.
            let receipt: ChatReceipt?
            let isUnsent: Bool
            switch message.status {
            case .sent:
                isUnsent = false
                // The newest confirmed, unsettled self message carries its status; the newest one the
                // counterpart has read carries "Read" even when a newer one is only delivered, so the
                // thread shows both lines at once.
                if message.stableID == latestSentFromSelfID {
                    receipt = Self.receipt(for: message.id, counterpartRead: counterpartRead)
                } else if message.stableID == latestReadFromSelfID, let read = counterpartRead {
                    receipt = Self.readReceipt(at: read.date)
                } else {
                    receipt = nil
                }
            case .sending:
                isUnsent = true
                // No status line while in flight — the bubble sits there until it resolves to
                // "Delivered" or the failed state.
                receipt = nil
            case .failed:
                isUnsent = true
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
                    part: part,
                    // The server still accepts reactions on a tombstone (spec: "Text, cash, media, reply
                    // and deleted messages take reactions"), and a deleted message keeps the pills it
                    // already has — only the long-press strip is withheld, and that already follows from
                    // a tombstone offering no context-menu actions. The pills sit under the message's
                    // last row, with its receipt.
                    reactions: isLast ? message.reactionState?.pills ?? [] : [],
                    selfReactions: message.reactionState?.selfReactions ?? [],
                    canReact: canReact,
                    isUnsent: isUnsent
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
        case .widget(.shareProfile):
            return ChatQuote(
                stableID: original.stableID,
                authorName: authorName,
                snippet: ChatQuote.sharedProfileSnippet,
                kind: .text,
                authorID: original.senderID
            )
        case .widget(.unrecognized):
            return ChatQuote(
                stableID: nil,
                authorName: authorName,
                snippet: ChatQuote.unavailableSnippet,
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
    /// whitespace and punctuation. A message with no card is one row, as it always was.
    ///
    /// The punctuation touching the link and the whitespace past it go with the link — they were
    /// the gap and the brackets around a word that now has a row of its own. Every other link stays in whichever text row
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
            return [RowLayout(part: nil, text: nil, preview: LinkPreview(links: preview.links, mentions: preview.mentions))]
        }

        func isIn(_ set: CharacterSet, _ index: Int) -> Bool {
            guard let scalar = Unicode.Scalar(body.character(at: index)) else { return false }
            return set.contains(scalar)
        }
        // Punctuation touching the link first — the "." ending a sentence, the brackets or quotes
        // around it — then the gap. Punctuation past a space belongs to the words beside it.
        var leadingEnd = link.location
        while leadingEnd > 0, isIn(.punctuationCharacters, leadingEnd - 1) { leadingEnd -= 1 }
        while leadingEnd > 0, isIn(.whitespacesAndNewlines, leadingEnd - 1) { leadingEnd -= 1 }
        var trailingStart = NSMaxRange(link)
        while trailingStart < body.length, isIn(.punctuationCharacters, trailingStart) { trailingStart += 1 }
        while trailingStart < body.length, isIn(.whitespacesAndNewlines, trailingStart) { trailingStart += 1 }

        // The links and mentions inside `span`, re-based to its start. A row with neither keeps no
        // preview, so it takes the plain text cell.
        func textRow(_ kind: ChatMessagePart.Kind, _ span: NSRange) -> RowLayout? {
            let segment = body.substring(with: span)
            guard !segment.unicodeScalars.allSatisfy(Self.carriesNothing.contains) else { return nil }
            func rebased(_ range: NSRange) -> NSRange? {
                guard range.location >= span.location, NSMaxRange(range) <= NSMaxRange(span) else { return nil }
                return NSRange(location: range.location - span.location, length: range.length)
            }
            let links = preview.links.compactMap { detected in
                rebased(detected.range).map { DetectedLink(range: $0, url: detected.url) }
            }
            let mentions = preview.mentions.compactMap { mention in
                rebased(mention.range).map { DetectedMention(range: $0, username: mention.username) }
            }
            return RowLayout(
                part: kind,
                text: segment,
                preview: links.isEmpty && mentions.isEmpty ? nil : LinkPreview(links: links, mentions: mentions),
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

    /// What a text row may hold and still say nothing: a segment of only these is dropped, not
    /// drawn as a bubble of stray punctuation next to its card.
    nonisolated private static let carriesNothing = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

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
        return readReceipt(at: read.date)
    }

    /// "Read", with the time the counterpart read up to when it's known.
    nonisolated private static func readReceipt(at date: Date?) -> ChatReceipt {
        guard let date else { return .read(time: nil) }
        return .read(time: date.formattedRelatively(useTimeForToday: true))
    }
}
