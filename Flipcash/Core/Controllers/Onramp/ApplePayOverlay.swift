//
//  ApplePayOverlay.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore

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
