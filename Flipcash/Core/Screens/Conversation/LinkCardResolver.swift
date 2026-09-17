//
//  LinkCardResolver.swift
//  Flipcash
//

import Foundation
import FlipcashCore

/// Fills a link card in, without claiming it.
///
/// For a cash card the whole payload is already in `GetTokenAccountInfos` — amount, claim state,
/// issuer, mint metadata — `AccountInfo` already models all of it, and `Session.receiveCashLink`
/// already makes exactly this fetch before it moves any funds. So there is no proto change and no
/// backend work here; there is a fetch and a hard stop. Nothing on this path may call
/// `receiveCashLink`, because that claims the link, and a card that claims what it renders would
/// empty a link by scrolling past it. A token card asks `GetMint` for branding and nothing else.
///
/// The two kinds memoize in separate caches so an entropy and a mint address cannot collide on one
/// key, and each kind's lookup is the only thing that can write its own side.
///
/// Failure of any kind — offline, timeout, malformed entropy, an unknown mint, a kill switch —
/// returns the card unchanged, in its unresolved state. Neither card has an error state by design:
/// the link underneath is still tappable and still works.
actor LinkCardResolver {

    private let cashLookup: @Sendable (String) async throws -> LinkCard.Cash.Resolved
    private let mintLookup: @Sendable (PublicKey) async throws -> LinkCard.Token.Resolved

    private var cashCache: [String: LinkCard.Cash.State] = [:]
    private var tokenCache: [PublicKey: LinkCard.Token.State] = [:]

    init(
        cashLookup: @escaping @Sendable (String) async throws -> LinkCard.Cash.Resolved,
        mintLookup: @escaping @Sendable (PublicKey) async throws -> LinkCard.Token.Resolved
    ) {
        self.cashLookup = cashLookup
        self.mintLookup = mintLookup
    }

    /// The same card with its state filled in, or unchanged if the lookup fails.
    func resolve(_ card: LinkCard) async -> LinkCard {
        switch card {
        case .cash(let cash):
            let state = await cashState(for: cash.entropy)
            return .cash(LinkCard.Cash(url: cash.url, entropy: cash.entropy, range: cash.range, state: state))

        case .token(let token):
            let state = await tokenState(for: token.mint)
            return .token(LinkCard.Token(url: token.url, mint: token.mint, range: token.range, state: state))
        }
    }

    /// Forgets what a cash link's lookup answered, so the next ask goes back to the server.
    ///
    /// A claim state is the one part of a card that changes under it: a link someone else collects
    /// keeps reading "Tap to claim" until something asks again, and nothing arrives to say it
    /// should. Callers decide when — a claim settling on this device, and a slow re-ask while a
    /// claimable card is on screen.
    ///
    /// The token cache has no equivalent, because a mint's branding does not settle.
    func invalidateCash(entropy: String) {
        cashCache[entropy] = nil
    }

    private func cashState(for entropy: String) async -> LinkCard.Cash.State {
        if let cached = cashCache[entropy] { return cached }

        let state: LinkCard.Cash.State
        do {
            state = .resolved(try await cashLookup(entropy))
        } catch {
            state = .unresolved
        }

        cashCache[entropy] = state
        return state
    }

    private func tokenState(for mint: PublicKey) async -> LinkCard.Token.State {
        if let cached = tokenCache[mint] { return cached }

        let state: LinkCard.Token.State
        do {
            state = .resolved(try await mintLookup(mint))
        } catch {
            state = .unresolved
        }

        tokenCache[mint] = state
        return state
    }
}

// MARK: - State -

nonisolated extension LinkCard {

    /// The same card carrying whatever `states` already knows about it, keyed by ``resolutionKey``
    /// — so a re-map renders a card that has already resolved without asking again.
    ///
    /// A state of the wrong kind is ignored rather than trusted: the key namespace already keeps
    /// the two apart, and this is the second lock on it.
    func applying(_ states: [String: LinkCard.State]) -> LinkCard {
        guard let state = states[resolutionKey] else { return self }

        switch (self, state) {
        case (.cash(let cash), .cash(let cashState)):
            return .cash(Cash(url: cash.url, entropy: cash.entropy, range: cash.range, state: cashState))

        case (.token(let token), .token(let tokenState)):
            return .token(Token(url: token.url, mint: token.mint, range: token.range, state: tokenState))

        case (.cash, .token), (.token, .cash):
            return self
        }
    }

    /// The link identity this card resolves against, which is what the resolver memoizes on.
    ///
    /// Namespaced by kind because the two live in one dictionary on the way back to the transcript,
    /// and base58 says nothing about which kind wrote it.
    var resolutionKey: String {
        switch self {
        case .cash(let cash): "cash:\(cash.entropy)"
        case .token(let token): "token:\(token.mint.base58)"
        }
    }

    /// Whether this card still has a lookup outstanding.
    var isUnresolved: Bool {
        switch state {
        case .cash(let cash): cash == .unresolved
        case .token(let token): token == .unresolved
        }
    }

    /// How far this card's lookup got.
    var state: State {
        switch self {
        case .cash(let cash): .cash(cash.state)
        case .token(let token): .token(token.state)
        }
    }
}

// MARK: - Lookup -

/// The one call a cash card needs. `Client` conforms as-is; the point of the protocol is everything
/// it leaves out — `Session.receiveCashLink` and every other path that moves funds.
nonisolated protocol GiftCardAccountReading: Sendable {
    func fetchAccountInfo(type: AccountInfoType, owner: KeyPair, requestingOwner: KeyPair?) async throws -> AccountInfo
}

extension Client: GiftCardAccountReading {}

/// The one call a token card needs: read a mint's branding. Read-only for the same reason as
/// ``GiftCardAccountReading`` — a card renders, it does not transact.
nonisolated protocol MintMetadataReading: Sendable {
    func fetchMint(mint: PublicKey) async throws -> MintMetadata
}

extension Client: MintMetadataReading {}

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

    /// The mint query itself. The card says which currency the link opens, not what the reader
    /// holds of it: a balance printed into a transcript is the reader's own position at the moment
    /// the row scrolled by, and it would go stale in place while the wallet moved on.
    static func mintLookup(
        reader: any MintMetadataReading
    ) -> @Sendable (PublicKey) async throws -> LinkCard.Token.Resolved {
        { mint in
            let metadata = try await reader.fetchMint(mint: mint)

            return LinkCard.Token.Resolved(
                name: metadata.name,
                iconURL: metadata.imageURL,
                colors: metadata.billColors,
                isReserve: metadata.address == .usdf
            )
        }
    }
}
