//
//  PaidReactionSheet.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashUI
import FlipcashCore

/// Thrown to reset the SwipeControl knob without its success checkmark when the boost doesn't complete.
private struct PaidReactionNotPaid: Error {}

/// Boosts one of the user's reactions (node 10330:17698): the emoji, how the payment is split, the
/// currency it's paid from, a preset or custom USD amount, and a swipe. Tapping the emoji moves to the
/// user's next reaction on the message; the sheet closes once they have none left.
///
/// Thin environment-reading wrapper that hands the session container to ``PaidReactionSheetContent``,
/// whose `init` seeds the `@State` view model synchronously.
struct PaidReactionSheet: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let target: ReactionBoostTarget
    /// The user's current reactions on the message.
    let selfReactions: [SelfReaction]

    var body: some View {
        PaidReactionSheetContent(sessionContainer: sessionContainer, target: target, selfReactions: selfReactions)
    }
}

private struct PaidReactionSheetContent: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(RatesController.self) private var ratesController

    @State private var viewModel: ReactionBoostViewModel
    @State private var isShowingTokenSelection = false
    @State private var isEnteringCustomAmount = false
    @State private var customCents: UInt64?
    @State private var didSucceed = false

    let selfReactions: [SelfReaction]

    init(sessionContainer: SessionContainer, target: ReactionBoostTarget, selfReactions: [SelfReaction]) {
        self.selfReactions = selfReactions
        _viewModel = State(initialValue: ReactionBoostViewModel(
            sessionContainer: sessionContainer,
            target: target,
            selfReactions: selfReactions
        ))
    }

    var body: some View {
        PartialSheet(background: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 16) {
                    Text("Boost Reaction")
                        .font(.appDisplaySmall)
                        .foregroundStyle(Color.textMain)
                    VStack(spacing: 6) {
                        // A disabled Button dims its label, so a single reaction shows the pill
                        // on its own rather than as a disabled button.
                        if viewModel.canCycleEmoji {
                            Button {
                                viewModel.cycleEmoji()
                            } label: {
                                EmojiPill(emoji: viewModel.emoji ?? "")
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Switches to your next reaction")
                            Text("Tap to change")
                                .font(.default(size: 12, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                                .accessibilityHidden(true)
                        } else {
                            EmojiPill(emoji: viewModel.emoji ?? "")
                        }
                    }
                    Text(viewModel.splitDescription)
                        .font(.default(size: 14, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        // The sheet re-measures after the picker closes and would otherwise truncate to one line.
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    Text("Pay with:")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                    payWithButton
                        .id(viewModel.selectedBalance?.stored.mint)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .padding(.bottom, 18)

                presets
                    .padding(.bottom, 25)

                SwipeControl(text: "Swipe to Pay") {
                    switch await viewModel.submit() {
                    case .success:
                        didSucceed = true
                    case .failed:
                        throw PaidReactionNotPaid()
                    }
                }
                .disabled(!viewModel.canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.top, 40)
            .padding(.bottom, bottomPadding)
        }
        .onChange(of: selfReactions) { _, reactions in
            viewModel.updateSelfReactions(reactions)
            if reactions.isEmpty && !didSucceed { dismiss() }
        }
        .task(id: didSucceed) {
            guard didSucceed else { return }
            await PaymentSuccess.release { dismiss() }
        }
        .sheet(isPresented: $isShowingTokenSelection) {
            let options = viewModel.paymentOptions
            CurrencyPickerSheet(
                options: options,
                // The initial balance skips Dollars, so the wallet's selected token can differ.
                selectedMint: viewModel.selectedBalance?.stored.mint ?? .usdf,
                onSelect: { mint in
                    if let balance = options.first(where: { $0.stored.mint == mint }) {
                        viewModel.selectCurrencyAction(exchangedBalance: balance)
                    }
                    isShowingTokenSelection = false
                }
            )
        }
        .sheet(isPresented: $isEnteringCustomAmount) {
            MinimumBalanceAmountSheet(
                isPresented: $isEnteringCustomAmount,
                title: "Boost Reaction",
                hint: viewModel.splitDescription
            ) { amount in
                let cents = Self.cents(amount)
                customCents = cents
                viewModel.selectedCents = cents
            }
        }
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(ReactionBoostViewModel.presetCents, id: \.self) { cents in
                AmountPresetButton(isSelected: customCents == nil && viewModel.selectedCents == cents) {
                    customCents = nil
                    viewModel.selectedCents = cents
                } label: {
                    Text(displayed(cents).formattedDroppingZeroFraction())
                }
            }

            AmountPresetButton(isSelected: customCents != nil) {
                isEnteringCustomAmount = true
            } label: {
                if let customCents {
                    Text(displayed(customCents).formattedDroppingZeroFraction())
                } else {
                    Image.system(.ellipsis)
                }
            }
            .accessibilityLabel(
                customCents.map { "Custom amount, \(displayed($0).formattedDroppingZeroFraction())" } ?? "Custom amount"
            )
        }
    }

    /// The selected currency in a filled capsule, matching Android's pill.
    private var payWithButton: some View {
        Button {
            isShowingTokenSelection = true
        } label: {
            HStack(spacing: 4) {
                if let balance = viewModel.selectedBalance {
                    TokenIconWithName(
                        url: balance.stored.imageURL,
                        monogramID: balance.stored.mint.base58,
                        name: balance.stored.name,
                        iconSize: 16
                    )
                }
                Image.system(.chevronDown)
                    .font(.default(size: 12, weight: .bold))
                    .foregroundStyle(Color.textMain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// A USD-priced boost as the viewer reads it, in the display currency.
    private func displayed(_ cents: UInt64) -> FiatAmount {
        ratesController.displayCurrency.amount(.usd(Decimal(cents) / 100))
    }

    /// A USD amount in whole cents, rounded half-even.
    private static func cents(_ amount: FiatAmount) -> UInt64 {
        var scaled = amount.value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        return NSDecimalNumber(decimal: rounded).uint64Value
    }

    /// The design's 55 under the swipe, less whatever the sheet already holds back for the home indicator.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 55 - reserved)
    }
}

/// The reaction being boosted, drawn as a selected reaction pill at sheet scale.
private struct EmojiPill: View {

    let emoji: String

    var body: some View {
        Text(emoji)
            .font(.default(size: 24, weight: .medium))
            .padding(.horizontal, 17)
            .padding(.vertical, 8.5)
            .background(Color.white.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.38), lineWidth: 2.8))
    }
}
