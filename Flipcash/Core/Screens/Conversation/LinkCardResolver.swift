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
/// empty a link by scrolling past it. A token card asks `GetMint` for branding and nothing else. A
/// group card asks `GetChat` for the chat's public record, redacted, and never joins. A person card
/// asks `GetProfile` and nothing else: it caches no profile, opens no overlay and navigates nowhere,
/// which is why it does not go through `TipFlow`.
///
/// The kinds memoize in separate maps so an entropy and a mint address cannot collide on one
/// key, and each kind's lookup is the only thing that can write its own side.
///
/// Failure of any kind — offline, timeout, malformed entropy, an unknown mint, a kill switch —
/// answers unresolved and is then forgotten, so the next ask goes back to the server. Neither card
/// has an error state by design: the link underneath is still tappable and still works. Holding a
/// failure would let one bad moment decide the card for as long as the caller lives, which is the
/// conclusion Android reached first and for the same reason.
actor LinkCardResolver {

    private let cashLookup: @Sendable (String) async throws -> LinkCard.Cash.Resolved
    private let mintLookup: @Sendable (PublicKey) async throws -> LinkCard.Token.Resolved
    private let groupLookup: @Sendable (ConversationID) async throws -> GroupLinkFacts
    private let userLookup: @Sendable (LinkCard.User.Identity) async throws -> UserLinkFacts

    /// The query per key, not the answer.
    ///
    /// An actor serializes turns, not awaits: checking a cache, awaiting the lookup and writing the
    /// answer back spans a suspension point, so two callers arriving for one key both miss and both
    /// query. Memoizing the `Task` closes that — the second caller finds the first one's task and
    /// awaits it — and it is also what makes several rows quoting one link cost one query, a
    /// guarantee that used to be the load coordinator's `cardsInFlight`.
    ///
    /// The task is not cancelled when a caller stops awaiting it. `Task.value` propagates
    /// cancellation to the awaiting caller alone, so a recycled row abandons its await and the query
    /// still finishes for whoever asks next.
    private var cashQueries: [String: Task<LinkCard.Cash.State, Never>] = [:]
    private var tokenQueries: [PublicKey: Task<LinkCard.Token.State, Never>] = [:]
    private var groupQueries: [ConversationID: Task<GroupLinkFacts?, Never>] = [:]
    private var userQueries: [LinkCard.User.Identity: Task<UserLinkFacts?, Never>] = [:]

    init(
        cashLookup: @escaping @Sendable (String) async throws -> LinkCard.Cash.Resolved,
        mintLookup: @escaping @Sendable (PublicKey) async throws -> LinkCard.Token.Resolved,
        groupLookup: @escaping @Sendable (ConversationID) async throws -> GroupLinkFacts,
        userLookup: @escaping @Sendable (LinkCard.User.Identity) async throws -> UserLinkFacts
    ) {
        self.cashLookup = cashLookup
        self.mintLookup = mintLookup
        self.groupLookup = groupLookup
        self.userLookup = userLookup
    }

    /// How far a cash or token card's lookup got: resolved, or unresolved if it failed.
    ///
    /// A group or person card is not answered here. Its picture's bytes land after the lookup, from
    /// the main-actor avatar store, so ``LinkCardFeed`` presents it from ``group(_:)`` or ``user(_:)``
    /// instead.
    func resolve(_ card: LinkCard) async -> LinkCard.State {
        switch card {
        case .cash(let cash):   return .cash(await cashState(for: cash.entropy))
        case .token(let token): return .token(await tokenState(for: token.mint))
        case .group:
            assertionFailure("A group card resolves through group(_:), not resolve(_:)")
            return .group(.unavailable)
        case .user:
            assertionFailure("A person card resolves through user(_:), not resolve(_:)")
            return .user(.notFound)
        }
    }

    /// The group's public record, or nil if the lookup failed or the chat is gone.
    func group(_ chatID: ConversationID) async -> GroupLinkFacts? {
        if let query = groupQueries[chatID] { return await query.value }

        let lookup = groupLookup
        let query = Task<GroupLinkFacts?, Never> {
            try? await lookup(chatID)
        }
        groupQueries[chatID] = query

        let facts = await query.value
        if facts == nil, groupQueries[chatID] == query { groupQueries[chatID] = nil }
        return facts
    }

    /// The person a tip card link names, or nil if nobody owns it or the lookup failed.
    func user(_ identity: LinkCard.User.Identity) async -> UserLinkFacts? {
        if let query = userQueries[identity] { return await query.value }

        let lookup = userLookup
        let query = Task<UserLinkFacts?, Never> {
            try? await lookup(identity)
        }
        userQueries[identity] = query

        let facts = await query.value
        if facts == nil, userQueries[identity] == query { userQueries[identity] = nil }
        return facts
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
        cashQueries[entropy] = nil
    }

    private func cashState(for entropy: String) async -> LinkCard.Cash.State {
        if let query = cashQueries[entropy] { return await query.value }

        let lookup = cashLookup
        let query = Task<LinkCard.Cash.State, Never> {
            do { return .resolved(try await lookup(entropy)) } catch { return .unresolved }
        }
        // Written before the first await, so a second caller for this key finds it rather than
        // starting its own.
        cashQueries[entropy] = query

        let state = await query.value
        if state == .unresolved, cashQueries[entropy] == query { cashQueries[entropy] = nil }
        return state
    }

    private func tokenState(for mint: PublicKey) async -> LinkCard.Token.State {
        if let query = tokenQueries[mint] { return await query.value }

        let lookup = mintLookup
        let query = Task<LinkCard.Token.State, Never> {
            do { return .resolved(try await lookup(mint)) } catch { return .unresolved }
        }
        tokenQueries[mint] = query

        let state = await query.value
        if state == .unresolved, tokenQueries[mint] == query { tokenQueries[mint] = nil }
        return state
    }
}

// MARK: - Keys -

nonisolated extension LinkCard {

    /// The link identity this card resolves against, which is what the resolver memoizes on.
    ///
    /// Namespaced by kind because the two share one dictionary in ``LinkCardMemo``, and base58 says
    /// nothing about which kind wrote it.
    var resolutionKey: String {
        switch self {
        case .cash(let cash): Self.cashKey(entropy: cash.entropy)
        case .token(let token): "token:\(token.mint.base58)"
        case .group(let group): "group:\(group.chatID.description)"
        case .user(let user):
            switch user.identity {
            // Lowercased because the no-handle link is, and a handle already is.
            case .userID(let userID):     "user:id:\(userID.uuidString.lowercased())"
            case .username(let username): "user:handle:\(username.value)"
            }
        }
    }

    /// The same key from an entropy alone. A settled claim names the entropy and nothing else, so
    /// the one place that has to build a key without a card builds it here rather than by hand.
    static func cashKey(entropy: String) -> String { "cash:\(entropy)" }
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

/// The one call a group card needs: a chat's public record. Read-only like the others — a card
/// renders, it does not join — and asked with a view mode, so the card's read can be redacted.
nonisolated protocol GroupChatReading: Sendable {
    func getChat(owner: KeyPair, conversationID: ConversationID, viewMode: ConversationViewMode) async throws -> Conversation
}

extension FlipClient: GroupChatReading {}

/// The one call a person card needs: a public profile, by whichever identity the link spells.
/// Read-only like the others — a card renders, it does not cache the profile or open anything.
nonisolated protocol ProfileReading: Sendable {
    func fetchProfile(userID: UserID, owner: KeyPair) async throws -> Profile
    func fetchProfile(username: Username, owner: KeyPair) async throws -> Profile
}

extension FlipClient: ProfileReading {}

/// A handle nobody has claimed. The server answers it with an id-less `Profile.empty` rather than
/// an error, so the lookup turns that into one.
struct NoSuchAccount: Error {}

/// A chat id that names something other than a group. An invite link only ever names a group, so
/// anything else has no card to show.
private struct NotAGroup: Error {}

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

    /// The group query itself: `GetChat`, redacted, plus the name of the token its entry rule is
    /// held in.
    ///
    /// Redacted because the card shows no message, so none is fetched. The gating check for this
    /// card: the `GetChat` contract returns a group's record — title, picture, rules, roster
    /// summary — to every registered user whatever the mode, and the `.chat` deep link already
    /// reads it this way for a non-member.
    ///
    /// A rule naming a token whose metadata cannot be fetched fails the lookup, as a cash card
    /// with no mint metadata does: a card that states a requirement in a token it cannot name
    /// says less than no card.
    static func groupLookup(
        chats: any GroupChatReading,
        mints: any MintMetadataReading,
        viewer: KeyPair
    ) -> @Sendable (ConversationID) async throws -> GroupLinkFacts {
        { chatID in
            let conversation = try await chats.getChat(owner: viewer, conversationID: chatID, viewMode: .redacted)
            guard conversation.type == .group else { throw NotAGroup() }

            var mintName: String?
            if let mint = headline(for: conversation.rules?.listener ?? [])?.mint, mint != .usdf {
                mintName = try await mints.fetchMint(mint: mint).name
            }
            return GroupLinkFacts(conversation: conversation, headlineMintName: mintName)
        }
    }

    /// The profile query itself, and whose link it is.
    ///
    /// An unclaimed handle comes back as `Profile.empty`, whose `userID` is nil; that is not found,
    /// not a person with no name. Own-link detection compares against `viewerID`, the session's
    /// user, rather than against the identity in the URL, so a handle link to the viewer is caught
    /// as well as an id link.
    static func userLookup(
        profiles: any ProfileReading,
        viewer: KeyPair,
        viewerID: UserID
    ) -> @Sendable (LinkCard.User.Identity) async throws -> UserLinkFacts {
        { identity in
            let profile = switch identity {
            case .userID(let userID):     try await profiles.fetchProfile(userID: userID, owner: viewer)
            case .username(let username): try await profiles.fetchProfile(username: username, owner: viewer)
            }
            guard let userID = profile.userID else { throw NoSuchAccount() }
            return UserLinkFacts(profile: profile, userID: userID, isOwn: userID == viewerID)
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
