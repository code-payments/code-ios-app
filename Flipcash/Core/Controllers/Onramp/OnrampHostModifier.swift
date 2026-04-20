//
//  OnrampHostModifier.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// Root-level host for the invisible Coinbase Apple Pay WebView and the
/// Onramp verification sheet. Attach once on the logged-in branch so any
/// screen can drive a Coinbase onramp without owning the Apple Pay plumbing
/// or the verification flow.
struct OnrampHostModifier: ViewModifier {

    @Environment(OnrampCoordinator.self) private var onrampCoordinator
    @Environment(OnrampDeeplinkInbox.self) private var deeplinkInbox

    func body(content: Content) -> some View {
        @Bindable var onrampCoordinator = onrampCoordinator
        @Bindable var deeplinkInbox = deeplinkInbox
        return content
            .overlay {
                ApplePayOverlay(order: onrampCoordinator.coinbaseOrder) { event in
                    onrampCoordinator.receiveApplePayEvent(event)
                }
            }
            .sheet(isPresented: $onrampCoordinator.isShowingVerificationFlow) {
                VerifyInfoScreen(onrampCoordinator: onrampCoordinator)
            }
            .onChange(of: deeplinkInbox.pendingEmailVerification, initial: true) { _, verification in
                if let verification {
                    onrampCoordinator.applyDeeplinkVerification(verification)
                    deeplinkInbox.pendingEmailVerification = nil
                }
            }
    }
}
