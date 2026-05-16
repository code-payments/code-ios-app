//
//  OnrampHostModifier.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// Root-level host for the invisible Coinbase Apple Pay WebView and the
/// out-of-flow verification fallback sheet. Attach once on the logged-in
/// branch so the Apple Pay plumbing and the deeplink-driven verification
/// fallback are reachable from any screen without each screen having to own
/// them.
///
/// Inline verification (driven by `BuyAmountScreen`'s buy flow or
/// `CurrencyCreationWizardScreen`'s launch flow) is hosted by those screens
/// directly — each binds `.sheet(item:)` to its own
/// `VerificationViewModel?` so the sheet stacks correctly on top of whatever
/// sheet the user is currently in. The fallback sheet hosted here only opens
/// when a verification deeplink arrives while no inline flow is active.
struct OnrampHostModifier: ViewModifier {

    @Environment(CoinbaseService.self) private var coinbaseService
    @Environment(VerificationCoordinator.self) private var verificationCoordinator
    @Environment(OnrampDeeplinkInbox.self) private var deeplinkInbox

    func body(content: Content) -> some View {
        @Bindable var coordinator = verificationCoordinator
        content
            .overlay {
                ApplePayOverlay(order: coinbaseService.coinbaseOrder) { event in
                    coinbaseService.receiveApplePayEvent(event)
                }
            }
            .onChange(of: deeplinkInbox.pendingEmailVerification, initial: true) { _, _ in
                verificationCoordinator.receiveDeeplinkIfPending()
            }
            .sheet(item: $coordinator.fallbackViewModel.cancellingOnDismiss()) { vm in
                VerifyInfoScreen(viewModel: vm)
            }
    }
}
