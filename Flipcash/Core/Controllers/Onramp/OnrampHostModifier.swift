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
/// (Wallet → Discovery → Wizard → FundingSelection) the root-level sheet slot
/// is already taken. Screens that initiate an onramp (`PurchaseMethodSheet`
/// via the `.buy` router stack, `CurrencyCreationWizardScreen` for launch)
/// host the verification sheet themselves so it presents on top of whatever
/// sheet stack the user is already in.
struct OnrampHostModifier: ViewModifier {

    @Environment(OnrampCoordinator.self) private var onrampCoordinator
    @Environment(OnrampDeeplinkInbox.self) private var deeplinkInbox

    func body(content: Content) -> some View {
        content
            .overlay {
                ApplePayOverlay(order: onrampCoordinator.coinbaseOrder) { event in
                    onrampCoordinator.receiveApplePayEvent(event)
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
