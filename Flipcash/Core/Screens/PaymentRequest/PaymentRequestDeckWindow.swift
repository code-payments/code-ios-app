//
//  PaymentRequestDeckWindow.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Hosts the expanded deck in a window above the app's own, so its backdrop can cover the app bar's
/// back button, picture and title the way a long-pressed message's menu does. A screen overlay
/// can't: the navigation bar draws over everything the screen puts on top of itself.
@MainActor
@Observable
final class PaymentRequestDeckWindow {

    /// The deck's items, kept current while the window is up.
    var items: [PaymentRequestDeckItem] = []
    /// Where the expanded list goes, in screen coordinates: the screen's content area below the bar.
    var listFrame: CGRect = .zero

    private var window: UIWindow?

    /// Puts the window up over the app. Presenting twice is a no-op.
    func present(state: PaymentRequestDeckState, open: @escaping (PaymentRequestID) -> Void) {
        let scene = UIApplication.shared.firstWindowScene
        guard window == nil, let scene else { return }
        let host = UIHostingController(rootView: PaymentRequestDeckWindowContent(window: self, state: state, open: open))
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        // Above the app, below the dialogs `DialogWindow` raises at `.alert`.
        window.windowLevel = .normal + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    /// Takes the window down.
    func dismiss() {
        window?.isHidden = true
        window = nil
    }
}

private struct PaymentRequestDeckWindowContent: View {

    let window: PaymentRequestDeckWindow
    @Bindable var state: PaymentRequestDeckState
    let open: (PaymentRequestID) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ChatBackdropView()
                .opacity(state.progress)
                .contentShape(Rectangle())
                .onTapGesture { state.collapse() }
                .accessibilityLabel("Collapse requests")
                .accessibilityAddTraits(.isButton)

            PaymentRequestDeckOverlay(items: window.items, state: state, open: open)
                .frame(width: window.listFrame.width, height: window.listFrame.height)
                .padding(.leading, window.listFrame.minX)
                .padding(.top, window.listFrame.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }
}
