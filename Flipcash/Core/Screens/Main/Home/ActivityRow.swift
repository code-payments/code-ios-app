//
//  ActivityRow.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The single activity row used across every surface — the Wallet and Currency
/// Info "Recent" previews, the cross-token Activity history, and the per-token
/// Transaction history (Figma 8966:1910, ported from Android's `ActivityFeedRow`):
/// a 40pt avatar, the title + relative time, and a signed amount. A peer payment
/// reads "Tipped <name>" or "Sent to <name>" once the counterparty resolves, and a
/// conversion reads "<From> → <To>" once both token names resolve.
///
/// Tapping a row pushes ``TransactionDetailsScreen`` onto whichever stack the row
/// is drawn on, which draws the same avatar at header size from the same
/// ``ActivityResolution``. The tap lives here rather than at each of the three
/// call sites so a row opens the same screen wherever it is shown.
struct ActivityRow: View {

    let activity: Activity

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router
    private var session: Session { sessionContainer.session }

    @State private var resolution = ActivityResolution()

    var body: some View {
        Button {
            router.push(.transactionDetails(activity))
        } label: {
            content
        }
        .buttonStyle(.plain)
        .task(id: activity.id) {
            await resolution.resolve(activity: activity, in: sessionContainer)
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            ActivityAvatar(activity: activity, resolution: resolution)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Text(activity.date.formattedRelatively(useTimeForToday: true))
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 8)

            amount
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Amount

    /// A conversion shows the converted (From) fiat amount over its fee; every
    /// other row shows its amount. Every figure is in the viewer's own currency, so
    /// a tip of 7,500 pesos reads "-$5.00" to a viewer in dollars.
    ///
    /// Converted here rather than where the feed is mapped so that a currency
    /// changed on a screen stacked over the list reaches these rows: reading
    /// ``RatesController`` in the body is what subscribes them to it.
    @ViewBuilder private var amount: some View {
        let display = ratesController.displayCurrency
        if let swap = activity.swapMetadata {
            VStack(alignment: .trailing, spacing: 2) {
                Text(display.amount(swap.fromFiat).formatted())
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                Text("-\(display.amount(swap.fee).formatted()) Fee")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        } else {
            Text(display.amount(activity.exchangedFiat).formatted(signPrefix: activity.kind.signPrefix))
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
        }
    }

    // MARK: - Title

    /// A peer payment renders with the resolved counterparty name, and a
    /// conversion renders its two token names, once they resolve; every other row
    /// uses the server-rendered title.
    private var displayTitle: String {
        if let swap = activity.swapMetadata {
            return Self.swapTitle(
                from: resolution.name(for: swap.fromMint, fallback: resolution.swapFromMint, session: session),
                to: resolution.name(for: swap.toMint, fallback: resolution.swapToMint, session: session)
            ) ?? activity.title
        }

        return Self.title(
            kind: activity.kind,
            boostedReaction: activity.boostedReaction,
            name: resolution.counterpartyName,
            chatName: boostChatName,
            serverTitle: activity.title
        ) ?? activity.title
    }

    /// The boosted chat's name, for a split boost only: a payment with a counterparty is named by
    /// that person. Read from the local chat store, never fetched; `nil` when the viewer has left
    /// the chat or it has not synced.
    private var boostChatName: String? {
        guard let boost = activity.boostedReaction, activity.counterparty == nil else { return nil }
        let controller = sessionContainer.conversationController
        return controller.conversation(withID: boost.conversationID).map(controller.displayName(for:))
    }

    /// The title of a peer payment row: the boost title when the payment boosted a reaction,
    /// else ``peerTitle(kind:name:serverTitle:)``. Returns `nil` when the caller should fall back
    /// to the server-rendered title.
    ///
    /// A boost wins over the tip verb check, and an unresolved name shows the no-name title
    /// rather than the server's.
    static func title(
        kind: Activity.Kind,
        boostedReaction: Activity.BoostedReaction?,
        name: String?,
        chatName: String?,
        serverTitle: String
    ) -> String? {
        guard let boostedReaction else {
            return peerTitle(kind: kind, name: name, serverTitle: serverTitle)
        }
        return boostTitle(kind: kind, emoji: boostedReaction.emoji, name: name, chatName: chatName)
    }

    /// How a boosted payment is titled: "Boosted 🔥 for Sally" / "Boost 🔥 from Sally" once the
    /// counterparty resolves, "Boosted 🔥 in Design Team" for a split boost whose chat is known,
    /// and "Boosted 🔥" / "Boost 🔥 received" when there is no name to use. Returns `nil` for a
    /// kind that cannot carry a boost.
    static func boostTitle(kind: Activity.Kind, emoji: String, name: String?, chatName: String?) -> String? {
        // Empty strings count as unresolved. No closures here: they would inherit the view's
        // main-actor isolation and trap when a test calls this off the main actor.
        let name = (name?.isEmpty ?? true) ? nil : name
        let chatName = (chatName?.isEmpty ?? true) ? nil : chatName

        switch kind {
        case .gave:
            if let name { return "Boosted \(emoji) for \(name)" }
            if let chatName { return "Boosted \(emoji) in \(chatName)" }
            return "Boosted \(emoji)"
        case .received:
            if let name { return "Boost \(emoji) from \(name)" }
            return "Boost \(emoji) received"
        default:
            return nil
        }
    }

    /// How a peer payment is titled once its counterparty resolves — "Tipped
    /// <name>" / "Tip from <name>" for a tip, "Sent to <name>" / "Received from
    /// <name>" for a plain send. Returns `nil` for a row that is not a peer
    /// payment, or whose counterparty has not resolved yet, so the caller falls
    /// back to the server-rendered title.
    ///
    /// The tip/send split rides on the server's verb alone — see
    /// ``Activity/isTipVerb(_:)``, which the details screen's kind reads too.
    static func peerTitle(kind: Activity.Kind, name: String?, serverTitle: String) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let isTip = Activity.isTipVerb(serverTitle)

        switch kind {
        case .gave:     return isTip ? "Tipped \(name)" : "Sent to \(name)"
        case .received: return isTip ? "Tip from \(name)" : "Received from \(name)"
        default:        return nil
        }
    }

    /// The conversion pair a swap row is titled with, or `nil` when either leg's
    /// token name is still unresolved — the caller falls back to the
    /// server-rendered title rather than showing a half-empty pair.
    static func swapTitle(from: String?, to: String?) -> String? {
        TransactionDetails.conversionTitle(from: from, to: to)
    }
}
