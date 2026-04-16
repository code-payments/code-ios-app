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

    static func forBuying(
        mint: PublicKey,
        displayName: String,
        session: Session,
        flipClient: FlipClient,
        deeplinkInbox: OnrampDeeplinkInbox,
        onDismiss: @escaping () -> Void
    ) -> OnrampAmountScreen {
        OnrampAmountScreen(
            viewModel: .forBuying(
                mint: mint,
                displayName: displayName,
                session: session,
                flipClient: flipClient,
                onDismiss: onDismiss
            ),
            onDismiss: onDismiss,
            deeplinkInbox: deeplinkInbox
        )
    }

    static func forLaunching(
        displayName: String,
        session: Session,
        flipClient: FlipClient,
        deeplinkInbox: OnrampDeeplinkInbox,
        onDismiss: @escaping () -> Void,
        onUsdfReady: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult
    ) -> OnrampAmountScreen {
        OnrampAmountScreen(
            viewModel: .forLaunching(
                displayName: displayName,
                session: session,
                flipClient: flipClient,
                onDismiss: onDismiss,
                onUsdfReady: onUsdfReady
            ),
            onDismiss: onDismiss,
            deeplinkInbox: deeplinkInbox
        )
    }

    private init(
        viewModel: OnrampViewModel,
        onDismiss: @escaping () -> Void,
        deeplinkInbox: OnrampDeeplinkInbox
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.onDismiss = onDismiss
        self.deeplinkInbox = deeplinkInbox
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
                case .launchProcessing(let swapId, let launchedMint, let currencyName, let amount):
                    CurrencyLaunchProcessingScreen(
                        swapId: swapId,
                        launchedMint: launchedMint,
                        currencyName: currencyName,
                        launchAmount: amount,
                        fundingMethod: .coinbase
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
