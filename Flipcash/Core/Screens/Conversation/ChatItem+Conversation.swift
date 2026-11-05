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

nonisolated private func detectedLink(in text: String, card: ([DetectedLink]) -> LinkCard?, page: MessageLinkPreview? = nil) -> LinkPreview? {
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
    let card = card(links) ?? page.flatMap { webCard(for: $0, in: text) }
    guard !links.isEmpty || !mentions.isEmpty || card != nil else { return nil }
    return LinkPreview(links: links, card: card, mentions: mentions)
}

/// The web card for the preview a message's sender attached, placed at the first whole-link
/// occurrence of its url, or nil when the text never holds it as one. No fetch rule applies here:
/// whatever the sender's platform previewed, the recipient draws.
nonisolated private func webCard(for page: MessageLinkPreview, in text: String) -> LinkCard? {
    guard !page.title.isEmpty,
          let range = LinkPreviewSendChecks.wholeLinkRange(url: page.url, in: text),
          let url = URL(string: page.url) else { return nil }
    return .web(LinkCard.Web(url: url, range: range, page: page))
}

extension ChatItem {

    /// Maps a conversation's messages to display-ready transcript items: resolves sender side,
    /// formats cash amounts, inserts a date separator before the first
    /// message, whenever a gap longer than `gap` opens and at every change of day, and computes
    /// same-sender grouping the way the transcript does. Pure — `cashBranding` supplies the token
    /// name + launchpad icon so this stays testable; it defaults to plain "Cash" (USDF), and the
    /// screen injects bonded-mint branding from `Session`. `viewerAmount` restates a payment in the
    /// display currency; it defaults to the amount as it moved, and the screen injects the
    /// conversion from ``RatesController``. `viewerPrice` does the same for a USD-priced amount, a
    /// reaction boost.
    nonisolated static func from(
        _ messages: [ConversationMessage],
        selfUserID: UserID,
        // How long a pause has to be before it heads the next message with its own separator and
        // ends the run above it. Android's `SeparatorConfig.Continuous` gap (one hour), so a pause of
        // minutes keeps one exchange together on both platforms instead of cutting it into single bubbles.
        gap: TimeInterval = 60 * 60,
        counterpartRead: (pointer: MessageID, date: Date?)? = nil,
        suppressReceiptFor: String? = nil,
        cashBranding: (ExchangedFiat) -> (token: String, iconURL: URL?) = { _ in ("Cash", nil) },
        viewerAmount: (ExchangedFiat) -> FiatAmount = { $0.nativeAmount },
        viewerPrice: (FiatAmount) -> FiatAmount = { $0 },
        deletedPresentation: DeletedMessagePresentation = .hidden,
        capabilities: (ConversationMessage) -> Set<MessageCapability> = { _ in [] },
        counterpartName: String = "",
        quotedMessage: (MessageID) -> ConversationMessage? = { _ in nil },
        author: (ConversationMessage) -> ChatAuthor? = { _ in nil },
        namesAuthors: Bool = false,
        /// The display name of a user a system notice names, or nil when none is known yet, which
        /// leaves the notice on the server's fallback text.
        nameOf: (UserID) -> String? = { _ in nil },
        /// Whether the viewer may add or remove a reaction — false for someone previewing a group
        /// they have not joined, or who fails a reaction-blocking speaker rule (see `ChatMessage.canReact`).
        canReact: Bool = true,
        /// Whether others' rows offer the leading "$" for a paid reaction. The viewer's own rows never do.
        canBoost: Bool = false,
        /// The card, if any, for a message's detected links. Injected like the other collaborators
        /// so the mapper stays pure; the screen supplies classification and nothing else, and it
        /// defaults to no card. Takes the detected links rather than the text so the detector runs
        /// once per message, here.
        linkCard: ([DetectedLink]) -> LinkCard? = { _ in nil },
        /// How a payment-request widget draws; resolved by the caller from the request store so
        /// the mapper stays pure. Defaults to the loading card.
        paymentRequest: (ConversationMessage) -> PaymentRequestCardState = { _ in .loading },
        /// The Send Back row under a cash message; nil draws none. See ``SendBackRow/resolve``.
        sendBack: (ConversationMessage) -> ChatCashContent.SendBack? = { _ in nil },
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
        // A message still waiting on the peer's key is left out until it decrypts, and a blank
        // system message draws nothing, so it must not head a separator either.
        let shown: [ConversationMessage] = switch deletedPresentation {
        case .hidden:      messages.filter { !$0.isDeleted && !$0.isAwaitingDecryption && !$0.isBlankSystem }
        case .placeholder: messages.filter { !$0.isAwaitingDecryption && !$0.isBlankSystem }
        }

        // Photos sent together draw as one card stack fronted by the first (see `ChatMediaGrouping`).
        // The photos behind it leave the list here, so receipts, runs and separators see one row; a
        // caption on the last stays that message's own text row under the stack, with its menu,
        // "Edited" marker, receipt and reactions.
        var stackMembers: [String: [ConversationMessage]] = [:]
        var captionRows: Set<String> = []
        var messages: [ConversationMessage] = []
        var cursor = 0
        for range in ChatMediaGrouping.stacks(in: shown) {
            messages += shown[cursor..<range.lowerBound]
            let members = Array(shown[range])
            stackMembers[members[0].stableID] = members
            messages.append(members[0])
            if let last = members.last, case .media(_, let caption?) = last.content, !caption.isEmpty {
                messages.append(last.replacingContent(.text(caption), lastEditedTs: last.lastEditedTs))
                captionRows.insert(last.stableID)
            }
            cursor = range.upperBound
        }
        messages += shown[cursor...]
        // A caption keeps the cards a caption draws: a cash, token or web link stays underlined text.
        func captionCard(_ links: [DetectedLink]) -> LinkCard? {
            switch linkCard(links) {
            case .cash, .token, .web, nil: nil
            case let card?: card
            }
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
        //
        // System rows are skipped when placing it: the divider heads the first real message after the
        // read-through, comparing against the nearest real message above, never a system row.
        func isSystem(_ message: ConversationMessage) -> Bool {
            if case .system = message.content { true } else { false }
        }
        let dividerHeadID: String? = {
            var older: ConversationMessage?
            for message in messages where !isSystem(message) {
                if let older, unreadBoundary.dividerBetween(newer: message, older: older, selfUserID: selfUserID) {
                    return message.stableID
                }
                older = message
            }
            return nil
        }()
        func divides(_ message: ConversationMessage, from earlier: ConversationMessage) -> Bool {
            message.stableID == dividerHeadID
        }

        // What breaks the bubble run: a text body of one to three emoji, on a row that is not a
        // reply — the quote panel lives inside the bubble and has no standalone layout. Narrower
        // than `ChatMessage.rendersAsLargeEmoji`, which also has a link row to rule out.
        func isEmojiOnlyBody(_ message: ConversationMessage) -> Bool {
            switch message.content {
            case .text(let text): EmojiOnlyDetector.isEmojiOnly(text)
            case .cash, .deleted, .encrypted, .widget, .media, .system: false
            }
        }
        // A system row has no sender, like a widget, so the author comparison below would otherwise
        // join a bubble to it (see `isSystem`).
        func rendersBare(_ message: ConversationMessage) -> Bool {
            message.repliedTo == nil && isEmojiOnlyBody(message)
        }

        // Each message's rows, worked out up front because a neighbour's first and last rows decide
        // whether a bubble here joins it. One row for most messages; a message with a link card is
        // split around it.
        let layouts = messages.map { message in
            switch message.content {
            case .text(let text):
                Self.rows(for: text, preview: detectedLink(
                    in: text,
                    card: { captionRows.contains(message.stableID) ? captionCard($0) : linkCard($0) },
                    page: message.linkPreview
                ))
            case .cash, .deleted, .encrypted, .widget, .media, .system: [RowLayout(part: nil, text: nil, preview: nil)]
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
                $0.senderID == message.senderID && !isSystem($0) && !showsSeparator && !showsDivider && !showsMarker
            } ?? false
            let groupedBelow = next.map {
                $0.senderID == message.senderID && !isSystem($0) && !separates($0, from: message) && !divides($0, from: message)
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
            case .system(let fallbackText, let event):
                let text = SystemNoticeStrings.text(
                    for: event,
                    fallbackText: fallbackText,
                    selfID: selfUserID,
                    nameOf: nameOf
                )
                let userLink = SystemNoticeStrings.userLink(for: event, text: text, selfID: selfUserID, nameOf: nameOf)
                items.append(.systemMessage(id: "sys-\(message.stableID)", text: text, serverID: message.id, userLink: userLink))
                continue
            case .text(let text):
                content = .text(text)
            case .cash(let fiat):
                let branding = cashBranding(fiat)
                let isTip = message.cashAction == .tipped
                var card = cashCard(
                    message.cashPayments,
                    receiver: message.cashReceiverID,
                    isFromSelf: isFromSelf,
                    isTip: isTip,
                    inGroup: namesAuthors,
                    total: fiat.nativeAmount,
                    shownAs: viewerAmount(fiat),
                    sender: author(message)?.name,
                    counterpartName: counterpartName,
                    selfUserID: selfUserID,
                    nameOf: nameOf
                )
                // A return is only ever posted into a DM, so it is named for the DM's two people.
                if message.cashReturn?.returnOf != nil, !namesAuthors {
                    card.lines = ChatCashContent.Lines.sentBack(isFromSelf: isFromSelf, counterpartName: counterpartName)
                }
                content = .cash(ChatCashContent(
                    amount: card.amount,
                    token: branding.token,
                    iconURL: branding.iconURL,
                    isTip: isTip,
                    lines: card.lines,
                    sendBack: sendBack(message)
                ))
            case .deleted(let deletion):
                content = .deleted(
                    deletion.deletedBy == selfUserID
                        ? "You deleted this message"
                        : "This message was deleted"
                )
            case .widget(.shareProfile(let share)):
                content = .shareProfile(LinkCard.User(profileOf: share.username))
            case .widget(.paymentRequest(let id)):
                switch paymentRequest(message) {
                case .loading:          content = .paymentRequest(ChatPaymentRequestContent(requestID: id.data, card: nil))
                case .card(let card):   content = .paymentRequest(ChatPaymentRequestContent(requestID: id.data, card: card))
                case .unsupported:      content = .unavailable(.updateApp)
                }
            case .widget(.unrecognized):
                // A widget variant this build doesn't draw; a newer one will.
                content = .unavailable(.updateApp)
            case .encrypted:
                // Still encrypted here means decryption failed; the awaiting ones were dropped above.
                content = .unavailable(.decryptFailure(
                    message.decryptFailure,
                    isFromSelf: isFromSelf,
                    // A group has no single counterpart, so name the message's own author.
                    senderName: author(message).map { $0.name.isEmpty ? counterpartName : $0.name } ?? counterpartName
                ))
            case .media(let attachments, let caption):
                // A redacted photo stays a photo row, drawn from its BlurHash, rather than a tombstone.
                // A send carries one attachment (see `ChatMediaSendPlan`); the row draws the first.
                let attachment = attachments.first
                // The detection a text body gets: links, mentions, and a Flipcash card, which draws
                // under the photo as the text path draws it: bare when the caption is only the link,
                // else split around it with the words in bubbles. A cash or token link stays
                // underlined text. A caption never carries a sender web card: a client sends the
                // text as its own message.
                let captionLayout = caption.map { Self.captionLayout(for: $0, card: linkCard) }
                content = .media(ChatMediaContent(
                    blobID: attachment?.blobID,
                    width: attachment?.width ?? 0,
                    height: attachment?.height ?? 0,
                    blurhash: attachment?.blurhash,
                    caption: caption,
                    captionPreview: captionLayout?.preview,
                    captionRows: captionLayout?.rows ?? [],
                    isRedacted: message.redacted,
                    sealed: attachment?.sealed,
                    stackPhotos: (stackMembers[message.stableID] ?? []).map { member in
                        let photo: MediaAttachment? = switch member.content {
                        case .media(let attachments, _): attachments.first
                        case .text, .cash, .deleted, .encrypted, .widget, .system: nil
                        }
                        let actions = capabilities(member)
                        let memberServerID: MessageID? = switch member.status {
                        case .sent:              member.id
                        case .sending, .failed:  nil
                        }
                        return ChatMediaStackPhoto(
                            messageID: member.stableID,
                            serverID: memberServerID,
                            blobID: photo?.blobID,
                            width: photo?.width ?? 0,
                            height: photo?.height ?? 0,
                            blurhash: photo?.blurhash,
                            isRedacted: member.redacted,
                            sealed: photo?.sealed,
                            canReply: actions.contains(.reply),
                            canForward: actions.contains(.forward)
                        )
                    }
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
                    viewerAmount: viewerAmount,
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
            var actionSet = capabilities(message)
            if stackMembers[message.stableID] != nil, actionSet.contains(.savePhoto) {
                actionSet.insert(.saveAllPhotos)
            }
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
                    actions: orderedActions(actionSet),
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
                    reactions: isLast ? (message.reactionState?.pills ?? []).map { $0.restatingBoost(viewerPrice) } : [],
                    selfReactions: message.reactionState?.selfReactions ?? [],
                    canReact: canReact,
                    // "$" boosts a reaction the viewer already has, so it waits for one.
                    canBoost: canBoost && !isFromSelf && message.senderID != nil && !message.isDeleted && !isUnsent
                        && !(message.reactionState?.selfReactions.isEmpty ?? true),
                    isUnsent: isUnsent,
                    sentAt: message.date
                )))
            }
        }
        return items
    }

    /// The pin bar's quote of a pinned `message`: the same author, snippet and kind a reply's quote
    /// of it carries, or "Encrypted message" for one this device can't open. `authorName` names a
    /// sender other than the viewer, as the reply strip resolves it.
    nonisolated static func pinQuote(
        of message: ConversationMessage,
        selfUserID: UserID,
        authorName: String,
        cashBranding: (ExchangedFiat) -> (token: String, iconURL: URL?),
        viewerAmount: (ExchangedFiat) -> FiatAmount
    ) -> ChatQuote {
        let quote = quote(
            resolving: message,
            selfUserID: selfUserID,
            counterpartName: authorName,
            cashBranding: cashBranding,
            viewerAmount: viewerAmount,
            author: { _ in nil }
        )
        guard case .encrypted = message.content else { return quote }
        return ChatQuote(
            stableID: message.stableID,
            authorName: quote.authorName,
            snippet: "Encrypted message",
            kind: .text,
            authorID: message.senderID
        )
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
        viewerAmount: (ExchangedFiat) -> FiatAmount,
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
            // Same amount and token the card carries, so the quote of a payment reads as that
            // payment. The launchpad icon is deliberately left out: it is a remote fetch.
            return ChatQuote(
                stableID: original.stableID,
                authorName: authorName,
                snippet: viewerAmount(fiat).formatted(),
                kind: .cash(token: cashBranding(fiat).token),
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
        case .widget(.paymentRequest):
            return ChatQuote(
                stableID: original.stableID,
                authorName: authorName,
                snippet: ChatQuote.paymentRequestSnippet,
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
        case .media(let attachments, let caption):
            // A redacted original's bytes may not be fetched, so its quote carries no thumbnail.
            return ChatQuote(
                stableID: original.stableID,
                authorName: authorName,
                snippet: ChatQuote.snippet(forText: ChatMediaStrings.quoteSnippet(caption: caption)),
                kind: .media(thumbnailBlobID: original.redacted ? nil : attachments.first?.blobID, sealed: attachments.first?.sealed),
                authorID: original.senderID
            )
        case .encrypted, .system:
            // No plaintext to preview -- same unavailable treatment as a quote whose original the
            // local database never saw. A notice offers no Reply, so a quote of one is unreachable.
            return ChatQuote(
                stableID: nil,
                authorName: authorName,
                snippet: ChatQuote.unavailableSnippet,
                kind: .unavailable,
                authorID: original.senderID
            )
        }
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
        // A web card draws inside the text bubble, under the text, with the link left in the text.
        if case .web = card {
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

    /// What a photo's caption draws: the preview a text body of the same words gets, and, when a
    /// non-money Flipcash card has words beside it, the rows the text path splits that message into.
    /// A card that is the whole caption keeps the preview and needs no rows; a cash or token card
    /// is dropped back to underlined link text.
    nonisolated static func captionLayout(
        for caption: String,
        card: ([DetectedLink]) -> LinkCard?
    ) -> (preview: LinkPreview?, rows: [ChatMediaCaptionRow]) {
        guard let preview = detectedLink(in: caption, card: card) else { return (nil, []) }
        guard let linkCard = preview.card else { return (preview, []) }
        let withoutCard = preview.links.isEmpty && preview.mentions.isEmpty
            ? nil
            : LinkPreview(links: preview.links, mentions: preview.mentions)
        let layout = rows(for: caption, preview: preview)
        if layout.count == 1, layout[0].part == .card { return (preview, []) }
        switch linkCard {
        case .cash, .token, .web:
            return (withoutCard, [])
        case .group, .message, .user:
            let split = layout.compactMap { row in
                row.part.flatMap { kind in
                    row.text.map { ChatMediaCaptionRow(kind: kind, text: $0, preview: row.preview) }
                }
            }
            return (withoutCard, split)
        }
    }

    /// What a text row may hold and still say nothing: a segment of only these is dropped, not
    /// drawn as a bubble of stray punctuation next to its card.
    nonisolated private static let carriesNothing = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

    /// Menu order is fixed here, not at the call site — a `Set` has no order, and the context menu
    /// must not shuffle its rows between renders of the same message.
    ///
    /// Forward follows Reply, as on Android, then Save Photo, and Pin after them. Report goes
    /// last: it is the rarest row and the only one that never appears on your own message, so the
    /// menu reads "yours ends with delete, theirs ends with report".
    nonisolated private static func orderedActions(_ capabilities: Set<MessageCapability>) -> [MessageCapability] {
        [.copy, .reply, .forward, .savePhoto, .saveAllPhotos, .pin, .unpin, .edit, .delete, .report, .silence, .remove].filter(capabilities.contains)
    }

    /// The large line and the lines around it for a cash card in the transcript. A group send to
    /// two or more draws the part each got with the total under it, or "~" the smallest part when
    /// the parts differ; a DM and a group send
    /// to one person draw the amount alone. Every card names the other side at its foot. `sender`
    /// is the author's name and `counterpartName` a DM's other member; either reads "Someone" when
    /// nil or empty.
    nonisolated static func cashCard(
        _ payments: [CashPayment],
        receiver: UserID?,
        isFromSelf: Bool,
        isTip: Bool,
        inGroup: Bool,
        total: FiatAmount,
        shownAs shown: FiatAmount,
        sender: String?,
        counterpartName: String,
        selfUserID: UserID,
        nameOf: (UserID) -> String?
    ) -> (amount: String, lines: ChatCashContent.Lines) {
        func named(_ name: String?) -> String { name.flatMap { $0.isEmpty ? nil : $0 } ?? "Someone" }
        let plainCaption = ChatCashContent.caption(isFromSelf: isFromSelf, isTip: isTip)
        guard inGroup else {
            let other = named(counterpartName)
            return (shown.formatted(), .init(caption: plainCaption, counterpart: isFromSelf ? "to \(other)" : "from \(other)"))
        }
        let senderName = named(sender)

        guard payments.count >= 2 else {
            // A receiver nobody can name, or none at all, is "Someone": the viewer is never told
            // they were paid unless the payment names them.
            let receiver = receiver ?? payments.first?.receiverID
            let receiverName = named(receiver.flatMap(nameOf))
            let lines: ChatCashContent.Lines = if isFromSelf {
                .init(caption: plainCaption, counterpart: "to \(receiverName)")
            } else if receiver == selfUserID {
                .init(caption: plainCaption, counterpart: "from \(senderName)")
            } else {
                .init(caption: "\(senderName) sent", counterpart: "to \(receiverName)")
            }
            return (shown.formatted(), lines)
        }

        // A part is restated by its share of `total`, so the part and the card's `shownAs` total
        // use one conversion.
        func restated(_ part: CashPayment) -> FiatAmount {
            total.value > 0
                ? FiatAmount(value: shown.value * Decimal(part.nativeAmount) / total.value, currency: shown.currency)
                : FiatAmount(value: shown.value / Decimal(payments.count), currency: shown.currency)
        }
        // Decided by the parts themselves, not the send's date: sends before every member got the
        // amount entered split a total, and a later send may split again.
        let isEven = payments.allSatisfy { $0.nativeAmount == payments[0].nativeAmount }
        let smallest = payments.min { $0.nativeAmount < $1.nativeAmount } ?? payments[0]
        let part: ChatCashContent.Lines.Part = isEven ? .each : .approximateEach
        let totalLine = "\(shown.formatted()) total"
        func others(_ count: Int) -> String { "\(count) \(count == 1 ? "other" : "others")" }

        let lines: ChatCashContent.Lines
        if !isFromSelf, payments.contains(where: { $0.receiverID == selfUserID }) {
            lines = .init(
                caption: "You and \(others(payments.count - 1)) received",
                total: totalLine,
                part: part,
                counterpart: "from \(senderName)"
            )
        } else {
            // Named by the first recipient in selection order.
            let lead = payments[0].receiverID.flatMap { $0 == selfUserID ? "You" : nameOf($0).flatMap { $0.isEmpty ? nil : $0 } }
            lines = .init(
                caption: isFromSelf ? plainCaption : "\(senderName) sent",
                total: totalLine,
                part: part,
                counterpart: lead.map { "to \($0) and \(others(payments.count - 1))" } ?? "to \(payments.count) people"
            )
        }
        // Every viewer, paid or not, sees the same part: the one each got, or "~" the smallest.
        return (restated(smallest).formatted(), lines)
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
