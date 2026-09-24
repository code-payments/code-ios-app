//
//  ChatLinkOpener.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation

/// Sends a link tapped in message text to the deep-link handler when it is one of ours, and to the
/// system otherwise.
///
/// iOS won't re-enter the app for our own universal link from an in-app tap, so our links have to
/// be routed by hand. Message text arrived through nothing, though, so only a link that passes
/// ``Route/isFlipcashLink(_:)`` is offered to the handler: `DeepLinkController.open` dedups,
/// records analytics, and hands the URL to the wallet callback before its own host gate runs, and
/// none of that is for `evil.com`.
struct ChatLinkOpener {

    /// Tries `url` as a deep link; returns whether it named an action.
    let openDeepLink: (URL) -> Bool

    /// Opens `url` outside the app.
    let openExternally: (URL) -> Void

    /// Routes one tapped link.
    func open(_ url: URL) {
        if Route.isFlipcashLink(url), openDeepLink(url) { return }
        openExternally(url)
    }
}
