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
private final class DetectedLinkBox {
    nonisolated let preview: LinkPreview?
    nonisolated init(_ preview: LinkPreview?) { self.preview = preview }
}

nonisolated(unsafe) private let linkPreviewCache: NSCache<NSString, DetectedLinkBox> = {
    let cache = NSCache<NSString, DetectedLinkBox>()
    cache.countLimit = 512
    return cache
}()

nonisolated private func detectedLink(in text: String) -> LinkPreview? {
    let key = text as NSString
    if let cached = linkPreviewCache.object(forKey: key) { return cached.preview }
    let preview = linkDetector.webLink(in: text)
    linkPreviewCache.setObject(DetectedLinkBox(preview), forKey: key)
    return preview
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
        namesAuthors: Bool = false
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

        // What breaks the bubble run: a text body of one to three emoji, on a row that is not a
        // reply — the quote panel lives inside the bubble and has no standalone layout. Narrower
        // than `ChatMessage.rendersAsLargeEmoji`, which also has a link row to rule out.
        func isEmojiOnlyBody(_ message: ConversationMessage) -> Bool {
            switch message.content {
            case .text(let text): EmojiOnlyDetector.isEmojiOnly(text)
            case .cash, .deleted: false
            }
        }
        func rendersBare(_ message: ConversationMessage) -> Bool {
            message.repliedTo == nil && isEmojiOnlyBody(message)
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
                $0.senderID == message.senderID && !showsSeparator
            } ?? false
            let groupedBelow = next.map {
                $0.senderID == message.senderID && !separates($0, from: message)
            } ?? false

            // The bubble run, which is not the author run. A bubble stacked above a bare emoji would
            // otherwise flatten its inner corner to `BubbleBackgroundView.groupedRadius` and take
            // the tight row gap, pointing at a bubble that is not there — while the name and the
            // gutter face stay where they are.
            let isBare = rendersBare(message)
            let joinsBubbleAbove = groupedAbove && !isBare && !(previous.map(rendersBare) ?? false)
            let joinsBubbleBelow = groupedBelow && !isBare && !(next.map(rendersBare) ?? false)

            let content: ChatMessage.Content
            let linkPreview: LinkPreview?
            switch message.content {
            case .text(let text):
                content = .text(text)
                linkPreview = detectedLink(in: text)
            case .cash(let fiat):
                let branding = cashBranding(fiat)
                content = .cash(ChatCashContent(
                    amount: fiat.nativeAmount.formatted(),
                    token: branding.token,
                    flagImageName: flagImageName(for: fiat),
                    iconURL: branding.iconURL,
                    isTip: message.cashAction == .tipped
                ))
                linkPreview = nil
            case .deleted(let deletion):
                content = .deleted(
                    deletion.deletedBy == selfUserID
                        ? "You deleted this message"
                        : "This message was deleted"
                )
                linkPreview = nil
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

            items.append(.message(ChatMessage(
                id: message.stableID,
                content: content,
                sender: isFromSelf ? .me : .other,
                isContinuationFromPrevious: groupedAbove,
                isContinuedByNext: groupedBelow,
                joinsBubbleAbove: joinsBubbleAbove,
                joinsBubbleBelow: joinsBubbleBelow,
                isEmojiOnly: isEmojiOnlyBody(message),
                receipt: receipt,
                linkPreview: linkPreview,
                isEdited: message.lastEditedTs != nil && !message.isDeleted,
                actions: orderedActions(capabilities(message)),
                quote: quote,
                // The viewer's own rows are never attributed: the trailing edge already says who
                // wrote them, and a name and avatar over them would read as a second speaker.
                author: isFromSelf ? nil : author(message),
                // Carried on every row of a group transcript, not just the ones that resolved an
                // author, so the gutter the faces sit in is held open for all of them and the
                // incoming bubbles share one leading edge.
                isAttributedTranscript: namesAuthors
            )))
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
        }
    }

    /// The currency's flag asset: a region flag where the currency has one, else the ticker, which
    /// is how the crypto flags are named. One derivation for the card and the quote so a payment
    /// keys the same way wherever it is drawn.
    nonisolated static func flagImageName(for fiat: ExchangedFiat) -> String {
        let currency = fiat.nativeAmount.currency
        return currency.region?.rawValue ?? currency.rawValue.uppercased()
    }

    /// Menu order is fixed here, not at the call site — a `Set` has no order, and the context menu
    /// must not shuffle its rows between renders of the same message.
    nonisolated private static func orderedActions(_ capabilities: Set<MessageCapability>) -> [MessageCapability] {
        [.copy, .reply, .edit, .delete].filter(capabilities.contains)
    }

    /// "Read 3:42 PM" / "Read Yesterday" / "Read Monday" / "Read Tue, Jun 17" once the counterpart's
    /// read pointer reaches the message, else "Delivered".
    nonisolated private static func receipt(for messageID: MessageID, counterpartRead: (pointer: MessageID, date: Date?)?) -> ChatReceipt {
        guard let read = counterpartRead, read.pointer >= messageID else { return .delivered }
        guard let date = read.date else { return .read(time: nil) }
        return .read(time: date.formattedRelatively(useTimeForToday: true))
    }
}
