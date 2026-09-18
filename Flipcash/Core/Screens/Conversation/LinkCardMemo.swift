//
//  LinkCardMemo.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// What the resolver has already answered about a link, readable without awaiting it.
///
/// ``LinkCardResolver`` memoizes for the whole session, but its cache lives behind an actor, and a
/// transcript maps synchronously and paints what it mapped. So a chat opened a second time asked
/// for an answer it already held and could not have it in time: the card painted unresolved, the
/// actor answered a hop later, and the reader saw a blank white ticket turn claimed under them.
///
/// This is the same answers on the main actor, where first paint can read them. The resolver stays
/// the one thing that *makes* an answer; this only remembers what came back, so the two cannot
/// disagree about a link — a re-ask lands here only when it lands there.
///
/// Container-scoped like the resolver, and grows with the links a session has looked at. A state is
/// two enum cases and a handful of short strings, and it is bounded by the cash and token links the
/// reader actually scrolled past, so there is nothing here worth evicting.
@MainActor
final class LinkCardMemo {

    /// Keyed by ``LinkCard/resolutionKey``, which is what the resolver memoizes on.
    private(set) var states: [String: LinkCard.State] = [:]

    /// Remembers what the resolver answered for `key`.
    ///
    /// Always an overwrite, never a merge: a re-ask exists precisely because the old answer went
    /// stale, so the newest answer is the only one worth keeping.
    func record(_ state: LinkCard.State, for key: String) {
        states[key] = state
    }
}
