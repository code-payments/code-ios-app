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
    @Environment(OnrampCoordinator.self) private var coordinator

    private let onDismiss: () -> Void

    // MARK: - Init -

    static func forBuying(
        mint: PublicKey,
        displayName: String,
        session: Session,
        coordinator: OnrampCoordinator,
        onUsdfReady: @escaping @MainActor @Sendable (Signature, ExchangedFiat) async throws -> SignedSwapResult,
        onDismiss: @escaping () -> Void
    ) -> OnrampAmountScreen {
        OnrampAmountScreen(
            viewModel: .forBuying(
                mint: mint,
                displayName: displayName,
                session: session,
                coordinator: coordinator,
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
        @Bindable var coordinator = coordinator
        NavigationStack {
            Background(color: .backgroundMain) {
                EnterAmountView(
                    mode: .onramp,
                    enteredAmount: $viewModel.enteredAmount,
                    subtitle: .singleTransactionLimit,
                    actionState: $viewModel.payButtonState,
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
                if !coordinator.isProcessingPayment {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ToolbarCloseButton { onDismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(coordinator.isProcessingPayment)
        }
        .dialog(item: $viewModel.dialogItem)
        .dialog(item: $coordinator.dialogItem)
        .onChange(of: coordinator.completion) { _, completion in
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
