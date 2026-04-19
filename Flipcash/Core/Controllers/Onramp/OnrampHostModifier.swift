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

    @Environment(OnrampCoordinator.self) private var coordinator
    @Environment(OnrampDeeplinkInbox.self) private var deeplinkInbox

    func body(content: Content) -> some View {
        @Bindable var coordinator = coordinator
        @Bindable var deeplinkInbox = deeplinkInbox
        return content
            .overlay {
                ApplePayOverlay(order: coordinator.coinbaseOrder) { event in
                    coordinator.receiveApplePayEvent(event)
                }
            }
            .sheet(isPresented: $coordinator.isShowingVerificationFlow) {
                VerifyInfoScreen(coordinator: coordinator)
            }
            .onChange(of: deeplinkInbox.pendingEmailVerification, initial: true) { _, verification in
                if let verification {
                    coordinator.applyDeeplinkVerification(verification)
                    deeplinkInbox.pendingEmailVerification = nil
                }
            }
    }
}
