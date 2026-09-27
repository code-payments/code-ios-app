//
//  CardSuggestionModel.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import Foundation
import Observation
import FlipcashCore
import FlipcashUI

/// Offers to send a person's card when the draft mentions their `@handle`, and holds the card once
/// the sender takes the offer.
///
/// The app never decides from the words alone whether a mention wants a card: "talk to @jeff" and
/// "hey @jeff" read the same to a parser. It offers, and the sender chooses. Taking the offer adds
/// the person's tip card link to the message, which every client already draws as a person card,
/// so nothing new goes over the wire.
@MainActor
@Observable
final class CardSuggestionModel {

    enum Phase: Equatable {
        /// Offered, not yet taken.
        case suggested
        /// Taken: the link goes out with the next send.
        case attached
    }

    /// The person on offer, or on the message.
    struct Suggestion: Equatable {
        let username: Username
        var person: LinkCard.User.Resolved
        var phase: Phase

        /// The link the card is sent as.
        var link: URL { URL.tipcard(for: person.userID, username: username) }
    }

    /// The strip's contents, or nil when there is nothing to offer.
    private(set) var suggestion: Suggestion?

    @ObservationIgnored private var source: (any LinkCardSource)?
    /// The person this chat is with, who is never offered: the card would only lead back here.
    @ObservationIgnored private var excluded: UserID?
    /// Handles the sender turned down in this draft. Cleared on send.
    @ObservationIgnored private var dismissed: Set<Username> = []
    /// The handle being looked up or on offer.
    @ObservationIgnored private var candidate: Username?
    @ObservationIgnored private var lookup: Task<Void, Never>?
    /// How long typing has to pause before a handle is looked up, so `@j`, `@je` and `@jef` on the
    /// way to `@jeff` do not each ask the server.
    @ObservationIgnored private let debounce: Duration

    init(debounce: Duration = .milliseconds(350)) {
        self.debounce = debounce
    }

    /// Where handles are looked up, and who to leave out.
    func connect(to source: any LinkCardSource, excluding counterpart: UserID?) {
        self.source = source
        self.excluded = counterpart
    }

    /// Re-reads the draft for a handle to offer. An attached card is left alone: the sender chose
    /// it, so editing the words around it does not take it back.
    func draftDidChange(_ text: String) {
        if suggestion?.phase == .attached { return }

        let next = Self.mentionedHandle(in: text, skipping: dismissed)
        guard next != candidate else { return }
        candidate = next
        lookup?.cancel()
        suggestion = nil

        guard let next, let source else { return }
        // Asked the way a person card in the transcript asks, so a handle already looked up there is
        // answered from the same memo. The id is unused: a link with a handle is built from it.
        let card = LinkCard.user(.init(
            url: URL.tipcard(for: UserID(), username: next),
            identity: .username(next),
            range: NSRange(location: 0, length: 0)
        ))
        let debounce = debounce
        lookup = Task { [weak self] in
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
            }
            guard !Task.isCancelled else { return }
            // Iterated rather than read once: the picture's bytes land after the profile does, and
            // the strip shows them when they arrive.
            for await state in source.states(for: card) {
                guard let self, !Task.isCancelled else { return }
                self.take(state, for: next)
            }
        }
    }

    /// Attaches the card on offer to the message.
    func accept() {
        suggestion?.phase = .attached
    }

    /// Turns down the offer, or takes an attached card back off the message. The handle is not
    /// offered again until the draft is sent.
    func dismiss() {
        if let username = suggestion?.username {
            dismissed.insert(username)
        }
        lookup?.cancel()
        candidate = nil
        suggestion = nil
    }

    /// Forgets the draft's offers once it is sent.
    func reset() {
        lookup?.cancel()
        candidate = nil
        dismissed = []
        suggestion = nil
    }

    /// The text to send for `submission`: the words, then the attached card's link on a line of
    /// its own, or the link alone when there are no words.
    func outgoing(_ submission: String?) -> String? {
        guard let suggestion, suggestion.phase == .attached else { return submission }
        let link = suggestion.link.absoluteString
        guard let submission else { return link }
        return "\(submission)\n\(link)"
    }

    /// Waits for the lookup in flight. For tests.
    func settle() async {
        await lookup?.value
    }

    private func take(_ state: LinkCard.State, for username: Username) {
        guard case .user(.resolved(let person)) = state, person.userID != excluded else {
            suggestion = nil
            return
        }
        if suggestion?.username == username {
            suggestion?.person = person
        } else {
            suggestion = Suggestion(username: username, person: person, phase: .suggested)
        }
    }

    // MARK: - Detection -

    /// An `@` at the start or after anything a handle or an address could not continue from — so
    /// `bob@example.com` is not a mention — then the handle's own characters. The character before
    /// the `@` is matched, not looked behind, because Swift's `Regex` has no lookbehind. Matched
    /// case-insensitively because people type `@Jeff`; ``Username`` itself is lowercase.
    private nonisolated(unsafe) static let mention = /(?:^|[^A-Za-z0-9_.@])@([A-Za-z0-9_]{2,15})(?![A-Za-z0-9_@])/

    /// The last handle in `text` that is well formed and not in `skipping`: the most recent mention
    /// is the one the sender is looking at.
    nonisolated static func mentionedHandle(in text: String, skipping: Set<Username> = []) -> Username? {
        text.matches(of: mention)
            .compactMap { Username(String($0.output.1).lowercased()) }
            .last(where: { !skipping.contains($0) })
    }
}
