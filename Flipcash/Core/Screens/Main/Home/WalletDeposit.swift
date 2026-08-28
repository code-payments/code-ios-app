//
//  WalletDeposit.swift
//  Flipcash
//

import Observation
import FlipcashCore

/// Carries a grabbed deposit from the bill overlay across to the wallet, so the
/// wallet can be seen to receive it.
///
/// A grab refreshes `Session.balances` while the bill is still on screen, so by
/// the time "Put in Wallet" brings the wallet forward the rise has already
/// happened out of sight. This records what the wallet was showing beforehand;
/// the wallet rewinds to those figures and plays the rise on arrival.
@Observable
final class WalletDeposit {

    /// A deposit that has reached the balances but has not yet been shown
    /// arriving on the wallet.
    struct Landing: Equatable {

        /// The token the deposit arrived in.
        let mint: PublicKey

        /// The wallet's total before it arrived — where the rise starts.
        let previousTotal: ExchangedFiat

        /// The tokens the wallet was already showing a card for.
        let previousMints: Set<PublicKey>

        /// Whether the deposit brings a token the wallet has no card for yet.
        var isNewToken: Bool { !previousMints.contains(mint) }
    }

    /// The deposit waiting to be played, or `nil` when none is in flight.
    private(set) var landing: Landing?

    /// Whether the user has asked for the wallet, releasing it to play.
    private(set) var isReleased = false

    /// The deposit the wallet has been released to play, or `nil` when nothing
    /// is waiting on it.
    var releasedLanding: Landing? { isReleased ? landing : nil }

    /// Records what the wallet is showing, ahead of a deposit landing in the balances.
    func arm(mint: PublicKey, previousTotal: ExchangedFiat, previousMints: Set<PublicKey>) {
        landing = Landing(mint: mint, previousTotal: previousTotal, previousMints: previousMints)
        isReleased = false
    }

    /// Releases the wallet to play the armed deposit — the user asked to put it in the wallet.
    func release() {
        guard landing != nil else { return }
        isReleased = true
    }

    /// Drops a deposit that was never released, leaving the wallet to track balances as usual.
    func discard() {
        guard !isReleased else { return }
        landing = nil
    }

    /// Clears the deposit once the wallet has played it.
    func consume() {
        landing = nil
        isReleased = false
    }
}
