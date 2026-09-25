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
/// **Host.** ``Route/flipcashHosts`` is checked against whatever the unwrap produced, on an exact
/// match. `Route.Path.parse` matches on path alone — deliberately, and its own doc comment says so,
/// because every URL it normally sees arrived through the associated-domains entitlement. Message
/// text arrived through nothing, so on its own `Route` would parse
/// `send.flipcash.com.evil.com/c/#/e=…` as `.cash`. The same gate stands in front of the tap
/// (``DeepLinkController``) and the QR scanner, so a card and a tap agree on which links are ours.
///
/// **Route.** Whatever survives the host gate goes to the real parser. No second path parser is
/// written.
///
/// Five paths become cards: `.cash`, `.token`, `.chat` (a group invite), and `.tip` / `.username` (a
/// person's tip card link). The rest are refused by name rather than by a
/// `default`, so a new route has to be ruled on here instead of inheriting a card. `.login` and
/// `.verifyEmail` in particular carry the account seed and a verification secret, and a card with a
/// tap target in front of either is a phishing aid.
nonisolated struct LinkCardClassifier {

    /// The first card-eligible link wins; at most one card per message.
    ///
    /// Takes the detected links rather than their URLs because the card carries the span it was
    /// built from, and the bubble draws the card in place of that span. A jump-wrapped link's text
    /// is the wrapper while its `url` is the target, so a later search for the URL would find
    /// nothing to remove.
    func firstCard(in links: [DetectedLink]) -> LinkCard? {
        links.lazy.compactMap { classify($0) }.first
    }

    /// Single-segment paths the website serves itself, which `Route` would otherwise read as
    /// handles. A deep link never meets these, because the AASA's `exclude` entries keep them out of
    /// the app; a link pasted into a message arrives through nothing. Android's
    /// `AppRouter.reservedProfilePaths` less the names `Route` already claims as its own paths.
    static let reservedPaths: Set<String> = [
        // The website's own pages.
        "download", "privacy", "terms", "support", "help", "about", "blog", "legal", "currencycreator",
        // Static roots and the web API, served off the apex alongside the pages.
        "app", "api", "assets", "fonts", "icons", "js", "v1",
        // Routes belonging to the app hosts.
        "pool",
    ]

    private func classify(_ link: DetectedLink) -> LinkCard? {
        let target = Route.unwrappingJump(link.url) ?? link.url

        guard let host = target.host()?.lowercased(), Route.flipcashHosts.contains(host) else { return nil }
        guard let route = Route(url: target) else { return nil }

        switch route.path {
        case .cash:
            guard let entropy = route.fragments[.entropy]?.value, !entropy.isEmpty else { return nil }
            return .cash(LinkCard.Cash(url: target, entropy: entropy, range: link.range))

        case .token(let mint):
            // A mint the server has never heard of is a card that never fills in, not a rejected
            // one: `Route` already proved the address is well-formed base58, and whether it names
            // anything is a question only the lookup can answer.
            return .token(LinkCard.Token(url: target, mint: mint, range: link.range))

        case .chat(let chatID):
            // A group invite. Whether the id names a group this viewer can see is, as with a mint,
            // a question for the lookup; a chat that turns out not to exist renders unavailable.
            return .group(LinkCard.Group(url: target, chatID: chatID, range: link.range))

        case .tip(let userID):
            // A person's link, by id: the no-handle form `URL.tipcard(for:username:)` builds, or the
            // legacy `/tip/<uuid>`. Whether anyone owns the id is the lookup's question.
            return .user(LinkCard.User(url: target, identity: .userID(userID), range: link.range))

        case .username(let username):
            // Only reached past the host gate above. `Route` parses any single-segment path as a
            // handle, so without that gate `discord.gg/<invite>` would be a person card.
            guard !Self.reservedPaths.contains(username.value) else { return nil }
            return .user(LinkCard.User(url: target, identity: .username(username), range: link.range))

        case .login, .verifyEmail, .chatSendCash,
             .give, .balance, .discover, .unknown:
            return nil
        }
    }
}
