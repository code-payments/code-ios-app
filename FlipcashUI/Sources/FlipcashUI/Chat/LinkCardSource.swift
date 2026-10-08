//
//  LinkCardSource.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import FlipcashCore

/// Where a link card gets its contents. Conformed to in the app target, which owns the lookup.
///
/// The card asks for itself rather than being handed an answer. A transcript that carried the
/// answer had to re-map and re-diff every row each time one landed, and had to hold its first paint
/// back so the cards on screen were not blank; a card that asks does neither, and the rows appear
/// the moment they are mapped.
///
/// This lives here, as a protocol, because the lookup does not: it needs `Client`, which is in the
/// app target, and this package cannot reach it.
@MainActor
public protocol LinkCardSource: AnyObject {

    /// What is already known about `card`, without suspending — nil if nothing is.
    ///
    /// The difference between a card that paints its answer straight away and one that shimmers
    /// while it waits. A link looked at once in this session is known for the rest of it, so
    /// scrolling back to a card does not make it flicker through a loading state it has outgrown.
    ///
    /// A failed lookup is not knowledge: it answers nil, and the next appearance asks again.
    func known(_ card: LinkCard) -> LinkCard.State?

    /// Every state `card` takes while the caller iterates, the first answer included.
    ///
    /// The first element is whatever the lookup returns, which for a known card is what ``known``
    /// already reported. Later elements are re-asks — a claim settling, or the slow refresh of a
    /// link still showing as claimable — so a card left on screen keeps up with the link under it.
    ///
    /// Ending the iteration unsubscribes and nothing more. The lookup behind it belongs to the
    /// source, not to any one card, so a row recycled mid-flight does not cancel the answer the
    /// next row to show that link is about to want.
    func states(for card: LinkCard) -> AsyncStream<LinkCard.State>

    /// The bytes of a web card's preview image, or nil when it cannot be fetched.
    func webImage(for url: URL) async -> Data?
}

extension LinkCardSource {

    /// The bytes of a web card's preview image, or nil when it cannot be fetched.
    ///
    /// Nil by default, so a source with no web lookup draws every web card without its image.
    public func webImage(for url: URL) async -> Data? { nil }
}

/// Whether a web card in this transcript looks its page up on its own or waits to be asked.
///
/// Never stored on the card or in the memo: a cached answer must not say who asked for it.
public enum WebLinkPreviewMode: Sendable, Equatable {
    /// Members of the chat, and anyone in a DM: the card asks as soon as it draws.
    case automatic
    /// A viewer outside the group: the card shows a chip and asks only once it is tapped.
    case tapToLoad
}

/// The web links a transcript's viewer has asked to preview through the chip.
///
/// Held by the transcript and shared by its rows, so a row recycled after the tap does not show the
/// chip again. Never persisted, and never part of the card or the memo.
@MainActor
public final class WebPreviewRequests {
    private var urls: Set<URL> = []

    public init() {}

    public func insert(_ url: URL) { urls.insert(url) }
    public func contains(_ url: URL) -> Bool { urls.contains(url) }
}
