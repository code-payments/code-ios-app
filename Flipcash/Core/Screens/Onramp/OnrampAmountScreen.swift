//
//  OnrampAmountScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-04-17.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct OnrampAmountScreen: View {

    @State private var viewModel: OnrampViewModel

    private let onDismiss: () -> Void
    private let deeplinkInbox: OnrampDeeplinkInbox

    // MARK: - Init -

    init(
        destination: OnrampViewModel.BuyDestination,
        session: Session,
        ratesController: RatesController,
        flipClient: FlipClient,
        deeplinkInbox: OnrampDeeplinkInbox,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        self.deeplinkInbox = deeplinkInbox
        _viewModel = State(wrappedValue: OnrampViewModel(
            destination: destination,
            session: session,
            ratesController: ratesController,
            flipClient: flipClient,
            onDismiss: onDismiss
        ))
    }

    // MARK: - Body -

    var body: some View {
        NavigationStack(path: $viewModel.amountPath) {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .onramp,
                    enteredAmount: $viewModel.enteredAmount,
                    subtitle: .singleTransactionLimit,
                    actionState: $viewModel.payButtonState,
                    actionEnabled: { _ in
                        viewModel.enteredFiat != nil
                    },
                    action: viewModel.customAmountEnteredAction,
                    currencySelectionAction: nil,
                )
                .foregroundColor(.textMain)
                .padding(20)
                .overlay {
                    ApplePayOverlay(order: viewModel.coinbaseOrder) { event in
                        viewModel.receiveApplePayEvent(event)
                    }
                }
            }
            .navigationTitle("Amount to Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.isProcessingPayment {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton { onDismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isProcessingPayment)
            .navigationDestination(for: OnrampAmountPath.self) { path in
                switch path {
                case .swapProcessing(let swapId, let currencyName, let amount):
                    SwapProcessingScreen(
                        swapId: swapId,
                        swapType: .buyWithCoinbase,
                        currencyName: currencyName,
                        amount: amount
                    )
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingVerificationFlow) {
            VerifyInfoScreen(viewModel: viewModel)
        }
        .dialog(item: $viewModel.dialogItem)
        .onChange(of: deeplinkInbox.pendingEmailVerification, initial: true) { _, verification in
            if let verification {
                viewModel.applyDeeplinkVerification(verification)
                deeplinkInbox.pendingEmailVerification = nil
            }
        }
    }
}

/// Invisible overlay that hosts the Coinbase Apple Pay WKWebView. The view is
/// rendered at zero opacity (it exists only to drive Apple Pay's JS payment
/// flow in the background) and explicitly excluded from hit testing and
/// accessibility so the covered region of the amount keypad remains tappable
/// and VoiceOver users don't land on a silent 300×300 zone.
private struct ApplePayOverlay: View {

    let order: OnrampOrderResponse?
    let onEvent: (ApplePayEvent) -> Void

    var body: some View {
        if let order {
            ApplePayWebView(url: order.paymentLink.url, onMessage: onEvent)
                .frame(width: 300, height: 300)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id(order.id)
        }
    }
}
