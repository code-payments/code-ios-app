//
//  ChatPreviewMapping.swift
//  FlipcashCore
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Display branding for a cash card's token: its name and optional coin icon, resolved by the
/// caller (e.g. the notification extension fetches it over the network).
public struct MintBrandingInfo: Sendable {
    public let name: String
    public let iconURL: URL?

    public init(name: String, iconURL: URL?) {
        self.name = name
        self.iconURL = iconURL
    }
}

extension ChatItem {

    /// Maps a flat list of `ConversationMessage` values to the last `limit` chat rows, sorted
    /// chronologically (oldest first), interleaved with date separators that open the transcript
    /// and mark gaps (matching the in-app chat). Intended for notification content-extension
    /// previews and other contexts that can link `FlipcashUI` but not the main app target.
    ///
    /// - Parameters:
    ///   - messages: The full or partial list of conversation messages in any order.
    ///   - selfUserID: The current user's ID; messages whose `senderID` matches are rendered on
    ///     the `.me` side.
    ///   - limit: Maximum number of rows to return. Defaults to 3. The *most recent* messages
    ///     (by `MessageID`) are kept, presented oldest-first.
    ///   - mintBranding: Resolved token branding (name + coin icon) keyed by mint, used to label
    ///     and illustrate cash rows (e.g. "Jeffy" with its icon). The caller resolves these over
    ///     the network; a cash row whose mint is absent shows no token label or icon.
    public static func preview(
        from messages: [ConversationMessage],
        selfUserID: UserID,
        limit: Int = 3,
        mintBranding: [PublicKey: MintBrandingInfo] = [:]
    ) -> [ChatItem] {
        // Drop tombstones before slicing so the preview keeps the newest `limit` *visible* messages —
        // filtering after `.suffix` would let a recent delete crowd out a real message (or blank the
        // preview) and leave an orphaned leading separator.
        let sorted = messages
            .filter { if case .deleted = $0.content { false } else { true } }
            .sorted { $0.id < $1.id }
        let slice = sorted.suffix(limit)

        var items: [ChatItem] = []
        var previous: ConversationMessage?
        for message in slice {
            // A separator opens the transcript and breaks any run whose gap from the previous
            // message exceeds `separatorGap`, mirroring the in-app `ChatItem.from`.
            if previous.map({ message.date.timeIntervalSince($0.date) > separatorGap }) ?? true {
                items.append(.dateSeparator(id: "sep-\(message.id.value)", text: separatorText(for: message.date)))
            }

            let sender: ChatMessage.Sender = message.senderID == selfUserID ? .me : .other

            let content: ChatMessage.Content
            switch message.content {
            case .text(let text):
                content = .text(text)
            case .cash(let fiat):
                // The flag loads from the FlipcashUI bundle, so it resolves inside an extension. The
                // token name + coin icon come from `mintBranding`; an unresolved mint shows no token
                // label or icon rather than a misleading fallback.
                let currency = fiat.nativeAmount.currency
                let branding = mintBranding[fiat.mint]
                content = .cash(ChatCashContent(
                    amount: fiat.nativeAmount.formatted(),
                    token: branding?.name ?? "",
                    flagImageName: currency.region?.rawValue ?? currency.rawValue.uppercased(),
                    iconURL: branding?.iconURL
                ))
            case .deleted:
                continue // filtered out above; unreachable, kept for switch exhaustiveness
            }

            items.append(.message(ChatMessage(
                id: String(message.id.value),
                content: content,
                sender: sender,
                isContinuationFromPrevious: false,
                isContinuedByNext: false
            )))
            previous = message
        }
        return items
    }

    /// Matches the in-app chat: a separator opens the transcript and breaks any run whose gap from
    /// the previous message exceeds this.
    private static let separatorGap: TimeInterval = 15 * 60

    /// The separator label for `date` — "Today 12:13 PM" / "Yesterday 9:05 AM" / "Jun 18 4:30 PM".
    /// Replicated from the app target's `ChatItem.from`, which this framework can't reach.
    private static func separatorText(for date: Date) -> String {
        let day: String
        if Calendar.current.isDateInToday(date) {
            day = "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            day = "Yesterday"
        } else {
            day = date.formatted(.dateTime.month().day())
        }
        return "\(day) \(date.formattedTime())"
    }
}
