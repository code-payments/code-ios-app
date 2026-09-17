//
//  LinkCardResolver.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Fills a cash link card in, without claiming it.
///
/// The whole payload is already in `GetTokenAccountInfos` — amount, claim state, issuer, mint
/// metadata — `AccountInfo` already models all of it, and `Session.receiveCashLink` already makes
/// exactly this fetch before it moves any funds. So there is no proto change and no backend work
/// here; there is a fetch and a hard stop. Nothing on this path may call `receiveCashLink`,
/// because that claims the link, and a card that claims what it renders would empty a link by
/// scrolling past it.
///
/// Failure of any kind — offline, timeout, malformed entropy, a kill switch — returns the card
/// unchanged, in its unresolved state. The card has no error state by design: the link underneath
/// is still tappable and still works.
actor LinkCardResolver {

    private let lookup: @Sendable (String) async throws -> LinkCard.Cash.Resolved
    private var cache: [String: LinkCard.Cash.State] = [:]

    init(lookup: @escaping @Sendable (String) async throws -> LinkCard.Cash.Resolved) {
        self.lookup = lookup
    }

    /// The same card with its state filled in, or unchanged if the lookup fails.
    func resolve(_ card: LinkCard) async -> LinkCard {
        switch card {
        case .cash(let cash):
            let state = await state(for: cash.entropy)
            return .cash(LinkCard.Cash(url: cash.url, entropy: cash.entropy, range: cash.range, state: state))
        }
    }

    private func state(for entropy: String) async -> LinkCard.Cash.State {
        if let cached = cache[entropy] { return cached }

        let state: LinkCard.Cash.State
        do {
            state = .resolved(try await lookup(entropy))
        } catch {
            state = .unresolved
        }

        cache[entropy] = state
        return state
    }
}

// MARK: - State -

nonisolated extension LinkCard {

    /// The same card carrying whatever `states` already knows about it, keyed the way the resolver
    /// caches — so a re-map renders a card that has already resolved without asking again.
    func applying(_ states: [String: LinkCard.Cash.State]) -> LinkCard {
        switch self {
        case .cash(let cash):
            guard let state = states[cash.entropy] else { return self }
            return .cash(Cash(url: cash.url, entropy: cash.entropy, range: cash.range, state: state))
        }
    }

    /// The link identity this card resolves against, which is what the resolver memoizes on.
    var resolutionKey: String {
        switch self {
        case .cash(let cash): cash.entropy
        }
    }

    /// Whether this card still has a lookup outstanding.
    var isUnresolved: Bool {
        state == .unresolved
    }

    /// How far this card's lookup got.
    var state: Cash.State {
        switch self {
        case .cash(let cash): cash.state
        }
    }
}

// MARK: - Lookup -

/// The one call a card needs. `Client` conforms as-is; the point of the protocol is everything it
/// leaves out — `Session.receiveCashLink` and every other path that moves funds.
nonisolated protocol GiftCardAccountReading: Sendable {
    func fetchAccountInfo(type: AccountInfoType, owner: KeyPair, requestingOwner: KeyPair?) async throws -> AccountInfo
}

extension Client: GiftCardAccountReading {}

extension LinkCardResolver {

    /// Entropy that isn't a mnemonic. Nothing to look up, so the card stays unresolved.
    private struct MalformedEntropy: Error {}

    /// The account query itself. Derivation mirrors `Session.receiveCashLink`, stopping at the fetch.
    ///
    /// Deliberately not wrapped in `Task.retry`: that retry exists because a just-funded gift card
    /// may not have propagated yet and the user is waiting on a claim. Here nobody is waiting and
    /// the card degrades to unresolved on its own.
    static func giftCardLookup(
        reader: any GiftCardAccountReading,
        viewer: KeyPair
    ) -> @Sendable (String) async throws -> LinkCard.Cash.Resolved {
        { entropy in
            guard let mnemonic = MnemonicPhrase(base58EncodedEntropy: entropy) else {
                throw MalformedEntropy()
            }
            let giftCardKeyPair = DerivedKey.derive(using: .solana, mnemonic: mnemonic).keyPair

            let info = try await reader.fetchAccountInfo(
                type: .giftCard,
                owner: giftCardKeyPair,
                requestingOwner: viewer
            )

            guard let exchangedFiat = info.exchangedFiat else { throw ErrorFetchBalance.notFound }
            // The card names and pictures the mint. A mint with no metadata gives neither, and a
            // card with an amount on it under no name says less than the brand mark does. Fail the
            // lookup and let it render unresolved instead.
            guard let mint = info.mintMetadata else { throw ErrorFetchBalance.notFound }

            let claim: LinkCard.Cash.Claim = switch info.claimState {
            case .claimed: .claimed
            case .expired: .expired
            default: .claimable
            }

            return LinkCard.Cash.Resolved(
                amount: exchangedFiat.nativeAmount.formatted(),
                claim: claim,
                // The reserve arrives already branded "Dollars" off the wire, which is what the
                // wallet card shows, so there is no special case here.
                tokenName: mint.name,
                iconURL: mint.imageURL
            )
        }
    }
}
