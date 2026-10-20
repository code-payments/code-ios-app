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

/// Pays for a reaction (node 10330:17698): the emoji, how the payment is split, the currency it's paid
/// from, a preset or custom USD amount, and a swipe.
///
/// Thin environment-reading wrapper that hands the session container to ``PaidReactionSheetContent``,
/// whose `init` seeds the `@State` view model synchronously.
struct PaidReactionSheet: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let target: ReactionBoostTarget

    var body: some View {
        PaidReactionSheetContent(sessionContainer: sessionContainer, target: target)
    }
}

private struct PaidReactionSheetContent: View {

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ReactionBoostViewModel
    @State private var isShowingTokenSelection = false
    @State private var isEnteringCustomAmount = false
    @State private var customCents: UInt64?
    @State private var didSucceed = false

    init(sessionContainer: SessionContainer, target: ReactionBoostTarget) {
        _viewModel = State(initialValue: ReactionBoostViewModel(sessionContainer: sessionContainer, target: target))
    }

    var body: some View {
        PartialSheet(background: .clear) {
            VStack(spacing: 25) {
                VStack(spacing: 12) {
                    Text(viewModel.target.emoji)
                        .font(.appDisplayLarge)
                    Text("Paid Reactions")
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                    Text(viewModel.splitDescription)
                        .font(.appTextBody)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 8) {
                    Text("Pay with:")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                    TokenSelectorButton(selectedBalance: viewModel.selectedBalance) {
                        isShowingTokenSelection = true
                    }
                    .id(viewModel.selectedBalance?.stored.mint)
                }

                presets

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
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, bottomPadding)
        }
        .task(id: didSucceed) {
            guard didSucceed else { return }
            try? await Task.delay(seconds: 1)
            guard !Task.isCancelled else { return }
            dismiss()
        }
        .sheet(isPresented: $isShowingTokenSelection) {
            SelectCurrencyScreen(isPresented: $isShowingTokenSelection) { balance in
                viewModel.selectCurrencyAction(exchangedBalance: balance)
            }
        }
        .sheet(isPresented: $isEnteringCustomAmount) {
            MinimumBalanceAmountSheet(
                isPresented: $isEnteringCustomAmount,
                title: "Paid Reaction",
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
                    Text(Self.usd(cents).formattedDroppingZeroFraction())
                }
            }

            AmountPresetButton(isSelected: customCents != nil) {
                isEnteringCustomAmount = true
            } label: {
                if let customCents {
                    Text(Self.usd(customCents).formattedDroppingZeroFraction())
                } else {
                    Image.system(.ellipsis)
                }
            }
            .accessibilityLabel(
                customCents.map { "Custom amount, \(Self.usd($0).formattedDroppingZeroFraction())" } ?? "Custom amount"
            )
        }
    }

    private static func usd(_ cents: UInt64) -> FiatAmount {
        .usd(Decimal(cents) / 100)
    }

    /// A USD amount in whole cents, rounded half-even.
    private static func cents(_ amount: FiatAmount) -> UInt64 {
        var scaled = amount.value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        return NSDecimalNumber(decimal: rounded).uint64Value
    }

    /// The design's 20 under the swipe, less whatever the sheet already holds back for the home indicator.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 20 - reserved)
    }
}
