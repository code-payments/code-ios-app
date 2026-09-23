//
//  CashLinkClaimReplies.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Replies to a cash link's message with a thank-you once the reader has collected it from this
/// transcript.
///
/// Nothing tells the sender their link was collected, and the card they are looking at only learns
/// on its next re-ask. A reply on the transcript reaches every participant on both platforms and
/// stays there, so it is how the claimer's device closes that loop; Android sends the same one.
///
/// A tap is not a claim: the reader can cancel the bill, or the link can turn out already taken.
/// So a tap records which message carried the voucher, and only a claim that settles as collected
/// sends anything. The pairing lives here because the claim itself comes back through the deep-link
/// path, which knows the entropy and nothing about a transcript.
@MainActor
final class CashLinkClaimReplies {

    static let thanks = "Thanks for the cash!"

    private let claims: CashLinkClaimLog
    private let reply: @MainActor (MessageID) -> Void

    /// The message each tapped, not-yet-settled voucher came on, by entropy.
    private var pending: [String: MessageID] = [:]

    /// Settled claims already acted on, so the log — which only grows — is read as the news in it.
    /// Seeded with what has settled before this transcript opened, which is nobody's reply here.
    private var honoredClaims: Set<String>

    init(claims: CashLinkClaimLog, reply: @escaping @MainActor (MessageID) -> Void) {
        self.claims = claims
        self.reply = reply
        self.honoredClaims = claims.settled
        observeSettledClaims()
    }

    /// Records that the reader opened the voucher `entropy` from `messageID`. The caller skips the
    /// reader's own messages, so nobody is thanked for collecting back their own link.
    func tapped(entropy: String, messageID: MessageID) {
        pending[entropy] = messageID
    }

    // Consumes the tap on any settled claim, and replies only to one that collected.
    private func observeSettledClaims() {
        let settled = withObservationTracking {
            claims.settled
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSettledClaims() }
        }

        let news = settled.subtracting(honoredClaims)
        honoredClaims = settled
        for entropy in news {
            guard let messageID = pending.removeValue(forKey: entropy),
                  claims.collected.contains(entropy) else { continue }
            reply(messageID)
        }
    }
}
