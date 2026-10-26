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
    /// The request whose details show over the expanded deck. They open from this window so nothing
    /// of the deck draws over them; once they cover the screen the deck snaps back to the pill, so
    /// going back finds it minimized.
    var details: PaymentRequestSelection?

    private var window: UIWindow?

    /// Puts the window up over the app. Presenting twice is a no-op.
    /// `details` builds a request's details screen with the environment it needs, which a second
    /// window doesn't inherit from the app's.
    func present<Details: View>(state: PaymentRequestDeckState, details: @escaping (PaymentRequestID) -> Details) {
        let scene = UIApplication.shared.firstWindowScene
        guard window == nil, let scene else { return }
        let content = PaymentRequestDeckWindowContent(window: self, state: state) { AnyView(details($0)) }
        let host = UIHostingController(rootView: content)
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
        details = nil
        window?.isHidden = true
        window = nil
    }
}

private struct PaymentRequestDeckWindowContent: View {

    @Bindable var window: PaymentRequestDeckWindow
    @Bindable var state: PaymentRequestDeckState
    let details: (PaymentRequestID) -> AnyView

    var body: some View {
        ZStack(alignment: .topLeading) {
            ChatBackdropView()
                .opacity(state.progress)
                .contentShape(Rectangle())
                .onTapGesture { state.collapse() }
                .accessibilityLabel("Collapse requests")
                .accessibilityAddTraits(.isButton)

            PaymentRequestDeckOverlay(items: window.items, state: state) { window.details = PaymentRequestSelection(id: $0) }
                .frame(width: window.listFrame.width, height: window.listFrame.height)
                .padding(.leading, window.listFrame.minX)
                .padding(.top, window.listFrame.minY)

            closeButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .fullScreenCover(item: $window.details, onDismiss: state.endPresentation) {
            details($0.id)
                .background(AppearanceReader(didAppear: state.snapToPill))
        }
    }

    /// Sits where the app-bar pill does, so it reads as the pill turned into a close. It fades in
    /// with the backdrop and out over the first quarter of a collapse, before the front card gets
    /// back to the pill.
    @ViewBuilder
    private var closeButton: some View {
        if let pill = state.barFrame {
            let opacity = state.isOpen ? state.progress : max(0, (state.progress - 0.75) / 0.25)
            CloseButton(style: .glass) { state.collapse() }
                .accessibilityLabel("Collapse requests")
                .position(x: pill.maxX - pill.height / 2, y: pill.midY)
                .opacity(opacity)
                .allowsHitTesting(state.isOpen)
        }
    }
}

/// Calls `didAppear` once the screen it sits in has finished appearing, after any presentation
/// transition, which SwiftUI's `onAppear` doesn't wait for.
private struct AppearanceReader: UIViewControllerRepresentable {

    let didAppear: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(didAppear: didAppear)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {

        let didAppear: () -> Void

        init(didAppear: @escaping () -> Void) {
            self.didAppear = didAppear
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            didAppear()
        }
    }
}
