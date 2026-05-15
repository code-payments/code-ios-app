//
//  OnrampHostModifier.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// Root-level host for the invisible Coinbase Apple Pay WebView and the
/// email-verification deeplink subscription. Attach once on the logged-in
/// branch so the Apple Pay plumbing is reachable from any screen without
/// each screen having to own it.
///
/// The verification sheet is NOT hosted here — SwiftUI only allows one modal
/// sheet per presentation context, and when the user is several sheets deep
/// (Wallet → Discovery → Wizard → funding picker) the root-level sheet slot
/// is already taken. Each screen that owns the user's path into onramp hosts
/// the verification sheet itself so it presents on top of whatever sheet
/// stack the user is in: `BuyAmountScreen` for the buy flow (verification
/// fires when the user taps Apple Pay in `PurchaseMethodSheet`), and
/// `CurrencyCreationWizardScreen` for the launch flow.
struct OnrampHostModifier: ViewModifier {

    @Environment(CoinbaseService.self) private var coinbaseService
    @Environment(OnrampCoordinator.self) private var onrampCoordinator
    @Environment(OnrampDeeplinkInbox.self) private var deeplinkInbox

    func body(content: Content) -> some View {
        content
            .overlay {
                ApplePayOverlay(order: coinbaseService.coinbaseOrder) { event in
                    coinbaseService.receiveApplePayEvent(event)
                }
            }
            .onChange(of: deeplinkInbox.pendingEmailVerification, initial: true) { _, verification in
                if let verification {
                    onrampCoordinator.applyDeeplinkVerification(verification)
                    deeplinkInbox.pendingEmailVerification = nil
                }
            }
    }
}
