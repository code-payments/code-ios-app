//
//  DialogWindow.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-04-01.
//

import SwiftUI
import FlipcashUI

/// A window that presents `session.dialogItem` above all other
/// UI, including sheets. Uses `UIWindow.Level.alert` so it sits
/// on top of the main window regardless of SwiftUI's sheet queue.
@MainActor
final class DialogWindow {

    private var window: PassthroughWindow?

    init(sessionAuthenticator: SessionAuthenticator, windowScene: UIWindowScene) {
        let window = PassthroughWindow(windowScene: windowScene)
        self.window = window

        let rootView = DialogWindowContent(sessionAuthenticator: sessionAuthenticator)

        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .clear

        window.windowLevel = .alert
        window.rootViewController = host
        window.overrideUserInterfaceStyle = .dark
        window.isHidden = false
    }
}

// MARK: - Content -

private struct DialogWindowContent: View {

    let sessionAuthenticator: SessionAuthenticator

    private var session: Session? {
        if case .loggedIn(let container) = sessionAuthenticator.state {
            return container.session
        }
        return nil
    }

    // DialogPresenter is a separate view because @Bindable
    // requires a non-optional Observable value.
    var body: some View {
        if let session {
            DialogPresenter(session: session)
        }
    }
}

private struct DialogPresenter: View {

    @Bindable var session: Session

    var body: some View {
        Color.clear
            .dialog(item: $session.dialogItem)
    }
}

// MARK: - PassthroughWindow -

/// A window that passes through touches unless a presented
/// view (e.g. a sheet) is actually in the hierarchy. This
/// avoids any state-syncing — the decision is based on what
/// UIKit actually has on screen at the time of the touch.
private class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        // If the hit lands on the root hosting view itself
        // (the invisible Color.clear), pass through to the
        // main window. Only capture when a sheet or other
        // presented content is the hit target.
        return view == rootViewController?.view ? nil : view
    }
}
