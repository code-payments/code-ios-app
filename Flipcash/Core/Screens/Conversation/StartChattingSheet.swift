//
//  StartChattingSheet.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashUI
import FlipcashCore

/// Thrown to reset the SwipeControl knob without its success checkmark when the
/// send doesn't complete (errors stay put; not-found has already dismissed).
private struct StartChattingDismissed: Error {}

/// Confirms the one payment that opens a tip DM: the counterpart's fee, the
/// currency it's paid from, and a swipe.
///
/// There is no keypad here because there is nothing to enter — the fee is the
/// only amount this payment can be, and the bottom bar's "Send $X to Start
/// Chatting" has already named it. Every other send from the thread keeps the
/// full amount screen.
///
/// Thin environment-reading wrapper that hands the session container to
/// ``StartChattingSheetContent``, whose `init` seeds the `@State` view model
/// synchronously from the recipient being paid.
struct StartChattingSheet: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let target: SendTarget

    /// The fee resolved at the tap, so the sheet keeps showing the amount it was
    /// opened for once the send lands and the floor no longer applies.
    let fee: FiatAmount

    var body: some View {
        StartChattingSheetContent(
            sessionContainer: sessionContainer,
            target: target,
            fee: fee
        )
    }
}

private struct StartChattingSheetContent: View {

    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: SendAmountViewModel
    @State private var isShowingTokenSelection: Bool = false
    @State private var didSucceed: Bool = false

    private let fee: FiatAmount

    // MARK: - Init -

    init(
        sessionContainer: SessionContainer,
        target: SendTarget,
        fee: FiatAmount
    ) {
        self.fee = fee
        _viewModel = State(initialValue: SendAmountViewModel(
            sessionContainer: sessionContainer,
            target: target
        ))
    }

    // MARK: - Body -

    /// The floor the view model will enforce on the swipe, so the amount shown
    /// and the amount submitted can't drift. Falls back to the fee the sheet was
    /// opened with, which is what's left once the send creates the chat.
    private var amount: FiatAmount {
        viewModel.tipMinimum ?? fee
    }

    var body: some View {
        PartialSheet(prefersGlass: true) {
            VStack(spacing: 25) {
                VStack(spacing: 12) {
                    Text(amount.formatted())
                        .font(.appDisplayLarge)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)

                    // The selector borrows the toolbar's chrome on the amount
                    // screen; here there is no toolbar, so it carries its own
                    // border — otherwise the chevron is the only thing saying
                    // the currency can be changed.
                    TokenSelectorButton(selectedBalance: viewModel.selectedBalance) {
                        isShowingTokenSelection = true
                    }
                    .id(viewModel.selectedBalance?.stored.mint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .strokeBorder(
                                Metrics.inputFieldStrokeColor(highlighted: false),
                                lineWidth: Metrics.inputFieldBorderWidth(highlighted: false)
                            )
                    }
                }

                SwipeControl(text: "Swipe to Send") {
                    switch await viewModel.submit(entered: amount.value) {
                    case .success:
                        didSucceed = true
                    case .recipientNotFound:
                        dismiss()
                        throw StartChattingDismissed()
                    case .failed:
                        throw StartChattingDismissed()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, bottomPadding)
        }
        // Warm the verified rate proof while the sheet is being read, so the
        // swipe doesn't stall on a cold cache.
        .task { await viewModel.prewarmVerifiedRate() }
        // Hold the success checkmark briefly, then dismiss back to the chat —
        // which by then holds the payment that opened it. Tied to the view via
        // `.task` so a dismissal during the hold cancels the dismiss.
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
    }

    /// The design's 20 under the swipe, less whatever the sheet already holds
    /// back for the home indicator — stacking the two doubles the gap.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 20 - reserved)
    }
}
