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
    /// message and whenever a gap longer than `gap` opens, and computes same-sender grouping the
    /// way the transcript does. Pure — `cashBranding` supplies the token name + launchpad icon so
    /// this stays testable; it defaults to plain "Cash" (USDF), and the screen injects bonded-mint
    /// branding from `Session`.
    nonisolated static func from(
        _ messages: [ConversationMessage],
        selfUserID: UserID,
        gap: TimeInterval = 15 * 60,
        counterpartRead: (pointer: MessageID, date: Date?)? = nil,
        suppressReceiptFor: String? = nil,
        cashBranding: (ExchangedFiat) -> (token: String, iconURL: URL?) = { _ in ("Cash", nil) },
        deletedPresentation: DeletedMessagePresentation = .hidden,
        capabilities: (ConversationMessage) -> Set<MessageCapability> = { _ in [] },
        counterpartName: String = "",
        quotedMessage: (MessageID) -> ConversationMessage? = { _ in nil }
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
        var items: [ChatItem] = []
        for (index, message) in messages.enumerated() {
            let isFromSelf = message.isFromSelf(selfUserID)
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil

            // A separator opens the transcript and breaks any run longer than the gap.
            let showsSeparator = previous.map { message.date.timeIntervalSince($0.date) > gap } ?? true
            if showsSeparator {
                items.append(.dateSeparator(id: "sep-\(message.stableID)", text: message.date.formattedChatSeparator()))
            }

            let groupedAbove = previous.map {
                $0.isFromSelf(selfUserID) == isFromSelf && message.date.timeIntervalSince($0.date) <= gap
            } ?? false
            let groupedBelow = next.map {
                $0.isFromSelf(selfUserID) == isFromSelf && $0.date.timeIntervalSince(message.date) <= gap
            } ?? false

            let content: ChatMessage.Content
            let linkPreview: LinkPreview?
            switch message.content {
            case .text(let text):
                content = .text(text)
                linkPreview = detectedLink(in: text)
            case .cash(let fiat):
                let currency = fiat.nativeAmount.currency
                let flagName = currency.region?.rawValue ?? currency.rawValue.uppercased()
                let branding = cashBranding(fiat)
                content = .cash(ChatCashContent(
                    amount: fiat.nativeAmount.formatted(),
                    token: branding.token,
                    flagImageName: flagName,
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
                    counterpartName: counterpartName
                )
            }

            items.append(.message(ChatMessage(
                id: message.stableID,
                content: content,
                sender: isFromSelf ? .me : .other,
                isContinuationFromPrevious: groupedAbove,
                isContinuedByNext: groupedBelow,
                receipt: receipt,
                linkPreview: linkPreview,
                isEdited: message.lastEditedTs != nil && !message.isDeleted,
                actions: orderedActions(capabilities(message)),
                quote: quote
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
        counterpartName: String
    ) -> ChatQuote {
        guard let original else {
            return ChatQuote(
                stableID: nil,
                authorName: "",
                snippet: ChatQuote.unavailableSnippet,
                kind: .unavailable
            )
        }
        let authorName = original.isFromSelf(selfUserID) ? "You" : counterpartName
        switch original.content {
        case .text(let text):
            return ChatQuote(
                stableID: original.stableID,
                authorName: authorName,
                snippet: ChatQuote.snippet(forText: text),
                kind: .text
            )
        case .cash(let fiat):
            return ChatQuote(
                stableID: original.stableID,
                authorName: authorName,
                snippet: fiat.nativeAmount.formatted(),
                kind: .cash
            )
        case .deleted:
            return ChatQuote(
                stableID: nil,
                authorName: authorName,
                snippet: ChatQuote.deletedSnippet,
                kind: .unavailable
            )
        }
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
