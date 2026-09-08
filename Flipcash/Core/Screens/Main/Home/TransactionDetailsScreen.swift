//
//  TransactionDetailsScreen.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashUI
import FlipcashCore

/// One activity entry in full (Figma node 9708:105260) — what opens when a row is
/// tapped in the Wallet's Recent section, the cross-token history, or a token's
/// own history.
///
/// The header restates the entry the way the user would: the row's own avatar,
/// then who or what it was, then its other side where the heading hasn't already
/// said it, then how much and in which direction, then when and in which token.
/// The navigation title stays the literal "Details", so the entry names itself in
/// the header rather than in the bar.
///
/// Cancelling is the bar's trailing action rather than a control at the foot of
/// the scroll: it applies to the whole entry, not to anything in the receipt, and
/// below a variable-length card it would land somewhere different on every kind.
struct TransactionDetailsScreen: View {

    let activity: Activity

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    private var session: Session { sessionContainer.session }

    @State private var resolution = ActivityResolution()
    @State private var dialogItem: DialogItem?
    @State private var didCopyID = false

    /// How long the copy control stays on the checkmark before reverting.
    private static let copyConfirmationDuration: Duration = .seconds(1.5)

    /// The header avatar, twice the row's — the same drawing at the size Figma
    /// gives the header.
    private static let avatarSize: CGFloat = 80

    /// The gap between the cards, per Figma node 9708:118142 — tighter than the
    /// gap that separates the header from them.
    private static let cardSpacing: CGFloat = 8

    private var details: TransactionDetails {
        TransactionDetails(
            activity: activity,
            counterpartyName: resolution.counterpartyName,
            fromTokenName: fromTokenName,
            toTokenName: toTokenName,
        )
    }

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    header

                    // The cards are one block, at the tighter gap Figma sets
                    // between them; the header sits apart from that block, so
                    // its gap is the outer stack's rather than this one's.
                    VStack(spacing: Self.cardSpacing) {
                        receiptCard
                        idCard

                        if let userID = activity.counterparty?.userID, details.canViewInChat {
                            Button("View in Chat") {
                                // Pushed onto the stack this screen is already
                                // on, not routed to the Chat tab: a cross-stack
                                // jump swaps the tab out from under the
                                // transition, so the bar and the conversation
                                // list both show before the chat lands. Pushed,
                                // the chat arrives from the entry it belongs to
                                // and back returns here.
                                router.push(.tipConversationForUser(userID))
                            }
                            .buttonStyle(.filled05)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Details")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if details.canCancel {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel", action: confirmCancelAction)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textError)
                }
            }
        }
        .dialog(item: $dialogItem)
        .task(id: activity.id) {
            await resolution.resolve(activity: activity, in: sessionContainer, resolvingEntryToken: true)
        }
    }

    // MARK: - Header

    /// Who or what it was, then how much and when — two blocks rather than one
    /// evenly spaced stack, because the wider gap either side of the amount is
    /// what separates the two facts.
    private var header: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                // No token badge here, unlike the row: the line under the
                // amount already names the token, and Figma draws the header
                // avatar plain.
                ActivityAvatar(
                    activity: activity,
                    resolution: resolution,
                    size: Self.avatarSize,
                    showsTokenBadge: false
                )

                Text(details.title)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)

                if let subtitle = details.subtitle {
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: 8) {
                amount

                // When, and in which token — the mint is what "$20.00" alone
                // never says.
                HStack(spacing: 8) {
                    Text(activity.date.formattedRelatively(useTimeForToday: true))

                    if let tokenName {
                        // A drawn dot rather than a "•" glyph: the glyph's size
                        // and its offset from the baseline are the font's to
                        // decide, and this wants a small circle on the line.
                        Circle()
                            .fill(Color.textSecondary)
                            .frame(width: 3, height: 3)

                        HStack(spacing: 4) {
                            if let url = tokenImageURL {
                                RemoteImage(url: url)
                                    .frame(width: 16, height: 16)
                                    .clipShape(Circle())
                            }
                            Text(tokenName)
                        }
                    }
                }
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
    }

    /// The entry's amount in the viewer's own currency, with what actually moved
    /// underneath when the two differ — the same reading the row shows, at the
    /// size the header gives it.
    private var amount: some View {
        let amounts = details.amount.forViewer(
            preferredRate: ratesController.rateForBalanceCurrency(),
            rates: ratesController.cachedRates
        )

        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Flag(style: amounts.viewer.currency.flagStyle, size: .small)
                Text(amounts.viewer.formatted(signPrefix: details.signPrefix))
                    .font(.appDisplaySmall)
                    .foregroundStyle(Color.textMain)
            }

            if let transferred = amounts.transferred {
                HStack(spacing: 4) {
                    Flag(style: transferred.currency.flagStyle, size: .small)
                    Text(transferred.formatted(signPrefix: details.signPrefix))
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    // MARK: - Receipt

    /// The receipt rows, in the order Figma node 9708:117417 lists them. A value
    /// the entry doesn't carry leaves its row out rather than rendering an empty
    /// one — a conversion is the only kind with a fee and a received amount.
    private var receiptCard: some View {
        DetailsCard {
            ReceiptRow(label: "Currency", value: details.currency.rawValue.uppercased())
            ReceiptRow(label: "Exchange Rate", value: Self.rateFormatter.string(for: details.exchangeRate) ?? "")
            ReceiptRow(label: "Date", value: details.date.formatted(Self.dateFormat))
            ReceiptRow(label: "Tokens", value: details.tokenAmount.formattedQuantity())

            if let fee = details.fee {
                ReceiptRow(label: "Fee", value: fee.formatted())
            }
            if let received = details.received {
                ReceiptRow(label: "Received", value: received.formatted())
            }

            ReceiptRow(label: "Status", value: details.status.label)
        }
    }

    /// The entry's id, in its own card so the copy control has an obvious target.
    /// The id is long and meaningless to read, so it middle-truncates — both ends
    /// stay legible, which is what someone comparing it against a support ticket
    /// actually reads.
    private var idCard: some View {
        Button(action: copyID) {
            DetailsCard {
                HStack(spacing: 8) {
                    Text("ID")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)

                    Text(details.id)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Group {
                        if didCopyID {
                            Image.system(.circleCheck)
                                .renderingMode(.template)
                        } else {
                            Image.asset(.squareBehindSquare)
                                .renderingMode(.template)
                        }
                    }
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy transaction ID")
    }

    // MARK: - Token

    /// The mint's metadata fallback for the entry's own token — a conversion's
    /// header names the leg that was given up, which is the mint the entry
    /// carries.
    private var entryMintFallback: StoredMintMetadata? {
        activity.swapMetadata == nil ? resolution.entryMint : resolution.swapFromMint
    }

    private var tokenName: String? {
        resolution.name(for: activity.exchangedFiat.mint, fallback: entryMintFallback, session: session)
    }

    private var tokenImageURL: URL? {
        resolution.imageURL(for: activity.exchangedFiat.mint, fallback: entryMintFallback, session: session)
    }

    private var fromTokenName: String? {
        guard let swap = activity.swapMetadata else { return nil }
        return resolution.name(for: swap.fromMint, fallback: resolution.swapFromMint, session: session)
    }

    private var toTokenName: String? {
        guard let swap = activity.swapMetadata else { return nil }
        return resolution.name(for: swap.toMint, fallback: resolution.swapToMint, session: session)
    }

    // MARK: - Formatting

    /// The settled rate, at the precision a rate is quoted in — enough decimals
    /// to reproduce the amounts above it.
    private static let rateFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 6
        formatter.maximumFractionDigits = 6
        return formatter
    }()

    private static let dateFormat = Date.FormatStyle(date: .numeric, time: .shortened)

    // MARK: - Actions

    private func copyID() {
        UIPasteboard.general.string = details.id
        withAnimation(.easeInOut(duration: 0.15)) {
            didCopyID = true
        }
        Task {
            try? await Task.sleep(for: Self.copyConfirmationDuration)
            withAnimation(.easeInOut(duration: 0.15)) {
                didCopyID = false
            }
        }
    }

    private func confirmCancelAction() {
        guard let metadata = activity.cancellableCashLinkMetadata else { return }

        dialogItem = .alert(
            title: "Cancel \(activity.exchangedFiat.nativeAmount.formatted()) Transfer?",
            subtitle: "The money will be returned to your wallet."
        ) {
            .destructive("Cancel Transfer") {
                cancelCashLink(metadata: metadata)
            };
            .cancel()
        }
    }

    private func cancelCashLink(metadata: Activity.CashLinkMetadata) {
        Task {
            do {
                try await session.cancelCashLink(giftCardVault: metadata.vault)
                // The entry this screen is drawn from is now spent; the list it
                // was opened from reloads on the DB change behind us.
                dismiss()
            } catch {
                ErrorReporting.captureError(error, reason: "Failed to cancel cash link", metadata: [
                    "vault": metadata.vault.base58,
                ], userFacing: true)
                dialogItem = .error(
                    title: "Failed to Cancel Transfer",
                    subtitle: "Something went wrong. Please try again later"
                )
            }
        }
    }
}

// MARK: - Components -

/// One receipt line: what it is on the left, what it was on the right.
private struct ReceiptRow: View {

    let label: String
    let value: String

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
                .truncationMode(.middle)
        } label: {
            Text(label)
                .foregroundStyle(Color.textSecondary)
        }
        .font(.appTextSmall)
    }
}

/// The panel the receipt and the id sit in (Figma node 9708:117417) — a tint over
/// the background and a small radius, no outline: the cards are the only things on
/// the background, so a border would draw a boundary the fill already draws.
private struct DetailsCard<Content: View>: View {

    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
    }
}
