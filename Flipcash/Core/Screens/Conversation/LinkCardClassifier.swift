//
//  LinkCardClassifier.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Which link in a message, if any, becomes a card.
///
/// Three steps, in this order.
///
/// **Unwrap.** A `jump.flipcash.com/#source=` wrapper is resolved to its target *before* the host
/// gate. `Route` classifies the target by path alone, so gating the redirector instead would let
/// the wrapper pick the host behind it and put a branded card in front of it.
///
/// **Host.** ``cardHosts`` is checked against whatever the unwrap produced, on an exact match.
/// `Route.Path.parse` matches on path alone — deliberately, and its own doc comment says so,
/// because every URL it normally sees arrived through the associated-domains entitlement. Message
/// text arrived through nothing, so on its own `Route` would parse
/// `send.flipcash.com.evil.com/c/#/e=…` as `.cash`. `Route` is not widened for this: its rules are
/// right for routing, and a chat-rendering problem should not change where a tapped link goes.
///
/// **Route.** Whatever survives the host gate goes to the real parser. No second path parser is
/// written.
///
/// `.login` and `.verifyEmail` are excluded by omission — they carry the account seed and a
/// verification secret, and a card with a tap target in front of either is a phishing aid.
nonisolated struct LinkCardClassifier {

    /// The union of the hosts the two apps claim — iOS's associated-domains entitlement and
    /// Android's manifest intent filters. `www.flipcash.com` is Android-only for routing and is
    /// here anyway: whether a link *is* a Flipcash link is not a question about which app opens
    /// it, and the cross-platform fixture has to agree on one answer.
    static let cardHosts: Set<String> = [
        "app.flipcash.com",
        "send.flipcash.com",
        "flipcash.com",
        "www.flipcash.com",
        "jump.flipcash.com",
    ]

    /// The first card-eligible link wins; at most one card per message.
    ///
    /// Takes the detected links rather than their URLs because the card carries the span it was
    /// built from, and the bubble draws the card in place of that span. A jump-wrapped link's text
    /// is the wrapper while its `url` is the target, so a later search for the URL would find
    /// nothing to remove.
    func firstCard(in links: [DetectedLink]) -> LinkCard? {
        links.lazy.compactMap { classify($0) }.first
    }

    private func classify(_ link: DetectedLink) -> LinkCard? {
        let target = Route.unwrappingJump(link.url) ?? link.url

        guard let host = target.host()?.lowercased(), Self.cardHosts.contains(host) else { return nil }
        guard let route = Route(url: target), case .cash = route.path else { return nil }
        guard let entropy = route.fragments[.entropy]?.value, !entropy.isEmpty else { return nil }

        return .cash(LinkCard.Cash(url: target, entropy: entropy, range: link.range, state: .unresolved))
    }
}
