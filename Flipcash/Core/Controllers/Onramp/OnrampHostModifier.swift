//
//  OnrampHostModifier.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

/// Root-level host for the invisible Coinbase Apple Pay WebView. Attach once
/// on the logged-in branch so any screen can drive a Coinbase onramp without
/// owning the Apple Pay plumbing.
struct OnrampHostModifier: ViewModifier {

    @Environment(OnrampCoordinator.self) private var coordinator

    func body(content: Content) -> some View {
        content
            .overlay {
                ApplePayOverlay(order: coordinator.coinbaseOrder) { event in
                    coordinator.receiveApplePayEvent(event)
                }
            }
    }
}
