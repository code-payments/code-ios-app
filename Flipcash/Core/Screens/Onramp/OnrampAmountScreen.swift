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
    @Environment(OnrampCoordinator.self) private var onrampCoordinator

    private let onDismiss: () -> Void

    // MARK: - Init -

    static func forBuying(
        mint: PublicKey,
        displayName: String,
        session: Session,
        onrampCoordinator: OnrampCoordinator,
        onUsdfReady: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult,
        onDismiss: @escaping () -> Void
    ) -> OnrampAmountScreen {
        OnrampAmountScreen(
            viewModel: .forBuying(
                mint: mint,
                displayName: displayName,
                session: session,
                onrampCoordinator: onrampCoordinator,
                onUsdfReady: onUsdfReady
            ),
            onDismiss: onDismiss
        )
    }

    private init(
        viewModel: OnrampViewModel,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.onDismiss = onDismiss
    }

    // MARK: - Body -

    var body: some View {
        @Bindable var viewModel = viewModel
        @Bindable var onrampCoordinator = onrampCoordinator
        NavigationStack {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .onramp,
                    enteredAmount: $viewModel.enteredAmount,
                    subtitle: .singleTransactionLimit,
                    actionState: .constant(onrampCoordinator.isProcessingPayment ? .loading : .normal),
                    actionEnabled: { _ in viewModel.enteredFiat != nil },
                    action: viewModel.customAmountEnteredAction,
                    currencySelectionAction: nil,
                )
                .foregroundColor(.textMain)
                .padding(20)
            }
            .navigationTitle("Amount to Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !onrampCoordinator.isProcessingPayment {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton { onDismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(onrampCoordinator.isProcessingPayment)
        }
        .dialog(item: $viewModel.dialogItem)
        .dialog(item: $onrampCoordinator.dialogItem)
        .sheet(isPresented: $onrampCoordinator.isShowingVerificationFlow) {
            VerifyInfoScreen(onrampCoordinator: onrampCoordinator)
        }
        .onChange(of: onrampCoordinator.completion) { _, completion in
            guard case .buyProcessing = completion else { return }
            onDismiss()
        }
    }
}

/// Invisible overlay that hosts the Coinbase Apple Pay WKWebView. The view is
/// rendered at zero opacity (it exists only to drive Apple Pay's JS payment
/// flow in the background) and explicitly excluded from hit testing and
/// accessibility so the covered region of the amount keypad remains tappable
/// and VoiceOver users don't land on a silent 300×300 zone.
struct ApplePayOverlay: View {

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
