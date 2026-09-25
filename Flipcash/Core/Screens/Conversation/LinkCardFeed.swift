//
//  LinkCardFeed.swift
//  Flipcash
//

import Foundation
import UIKit
import FlipcashCore
import FlipcashUI

/// What a link card in the transcript asks for its contents, and what keeps it up to date.
///
/// One object over three that already existed: ``LinkCardResolver`` makes the answers,
/// ``LinkCardMemo`` holds them where first paint can read them synchronously, and
/// ``CashLinkClaimLog`` says when a claim settles on this device. `ConversationLoadCoordinator`
/// used to hold all three and push answers back through the mapping pass, which meant a lookup
/// landing re-mapped and re-diffed the whole window and a chat opening held its first paint back so
/// the cards on screen were not blank. The cards ask for themselves now, and the transcript carries no resolution state at all.
///
/// Container-scoped, like the resolver and the memo it wraps: a lookup belongs to the session that
/// started it, not to the row that happened to want it first, so a row recycled mid-flight abandons
/// its await and the answer is still there for the next row to show that link.
@MainActor
final class LinkCardFeed: LinkCardSource {

    /// How often a card the reader can still act on asks again, while they are looking at it. A
    /// link claimed on someone else's device sends nothing here, so a claimable card is only ever
    /// as fresh as the last ask; Android re-asks on the same cadence.
    private static let claimableRefresh: TimeInterval = 15

    private let resolver: LinkCardResolver
    private let memo: LinkCardMemo
    private let claims: CashLinkClaimLog
    private let groups: any GroupLinkPresenting
    private let users: any UserLinkPresenting

    /// What a group or person link's lookup fetched.
    private enum Fetched {
        case group(GroupLinkFacts)
        case user(UserLinkFacts)
    }

    /// What each group or person link's lookup fetched, by resolution key.
    ///
    /// Held as facts, not as a finished card, because the picture's bytes land after the lookup
    /// does. ``known(_:)`` presents from here on every paint, so a card shows them once they have.
    private var fetched: [String: Fetched] = [:]

    /// Group and person keys whose presentation is being observed, so each is watched once however
    /// many rows show it.
    private var observedPictures: Set<String> = []

    /// Who is listening to each key. A link quoted by two rows has two continuations and one query.
    private var listeners: [String: [UUID: AsyncStream<LinkCard.State>.Continuation]] = [:]

    /// The card behind each key currently on screen, which is what a refresh re-asks for. Rows drop
    /// out of here as they recycle, so the cadence spends requests on cards the reader is looking
    /// at rather than on every card the window happens to hold.
    private var subscribed: [String: LinkCard] = [:]

    /// Bumped whenever a key is invalidated. Every ask carries the generation it went out under, so
    /// a query already in flight when the claim settled cannot land its stale answer over the fresh
    /// one.
    private var generations: [String: Int] = [:]

    /// Settled claims already acted on, so the log — which only grows — is read as the news in it.
    private var honoredClaims: Set<String> = []

    private var claimRefreshTask: Task<Void, Never>?
    private var foregroundTask: Task<Void, Never>?

    init(
        resolver: LinkCardResolver,
        memo: LinkCardMemo,
        claims: CashLinkClaimLog,
        groups: any GroupLinkPresenting,
        users: any UserLinkPresenting
    ) {
        self.resolver = resolver
        self.memo = memo
        self.claims = claims
        self.groups = groups
        self.users = users
        observeSettledClaims()
        startClaimableRefresh()
    }

    isolated deinit {
        claimRefreshTask?.cancel()
        foregroundTask?.cancel()
    }

    // MARK: - LinkCardSource -

    func known(_ card: LinkCard) -> LinkCard.State? {
        switch card {
        case .cash, .token:
            memo.states[card.resolutionKey]
        case .group, .user:
            fetched[card.resolutionKey].map(present)
        }
    }

    func states(for card: LinkCard) -> AsyncStream<LinkCard.State> {
        let key = card.resolutionKey
        let id = UUID()
        let (stream, continuation) = AsyncStream<LinkCard.State>.makeStream()

        listeners[key, default: [:]][id] = continuation
        subscribed[key] = card
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.unsubscribe(id, from: key) }
        }

        ask(card)
        return stream
    }

    // MARK: - Asking -

    // One ask per subscription, deduplicated by the resolver rather than here: it memoizes the
    // query, so the second row to quote a link awaits the first row's answer instead of asking for
    // its own.
    private func ask(_ card: LinkCard) {
        let key = card.resolutionKey
        let generation = generations[key, default: 0]
        switch card {
        case .cash, .token:
            Task { [resolver] in
                let state = await resolver.resolve(card)
                deliver(state, for: key, generation: generation)
            }
        case .group(let group):
            Task { [resolver] in
                let facts = await resolver.group(group.chatID)
                deliverFetched(facts.map(Fetched.group), missing: .group(.unavailable), for: key)
            }
        case .user(let user):
            Task { [resolver] in
                let facts = await resolver.user(user.identity)
                deliverFetched(facts.map(Fetched.user), missing: .user(.notFound), for: key)
            }
        }
    }

    // Where every cash and token answer lands: into the memo, so the next card to show this link
    // paints it without shimmering, and out to whoever is listening. Only a resolved answer is
    // remembered — a failure is forgotten so the next appearance asks again, which is what Android
    // does and the reason neither platform leaves a card dead for the visit after one bad moment
    // offline.
    private func deliver(_ state: LinkCard.State, for key: String, generation: Int) {
        guard generation == generations[key, default: 0] else { return }
        if state.isResolved {
            memo.record(state, for: key)
        }
        listeners[key]?.values.forEach { $0.yield(state) }
    }

    // A group's or person's facts land here rather than in the memo, and are presented per
    // listener. A failed lookup is forgotten like any other: the card shows `missing`, and the next
    // appearance asks again.
    private func deliverFetched(_ facts: Fetched?, missing: LinkCard.State, for key: String) {
        guard let facts else {
            listeners[key]?.values.forEach { $0.yield(missing) }
            return
        }
        fetched[key] = facts
        let state = present(facts)
        listeners[key]?.values.forEach { $0.yield(state) }
        observePicture(key)
        Task { await loadPicture(for: facts) }
    }

    private func present(_ facts: Fetched) -> LinkCard.State {
        switch facts {
        case .group(let group): .group(.resolved(groups.present(group)))
        case .user(let user):   .user(.resolved(users.present(user)))
        }
    }

    private func loadPicture(for facts: Fetched) async {
        switch facts {
        case .group(let group): await groups.loadPicture(for: group)
        case .user(let user):   await users.loadPicture(for: user)
        }
    }

    // Re-presents a group or person card when the picture's bytes land, and yields it to whoever is
    // still listening. Re-arms once per change, and lapses once no row shows the link.
    private func observePicture(_ key: String) {
        guard !observedPictures.contains(key), let facts = fetched[key] else { return }
        observedPictures.insert(key)

        withObservationTracking {
            _ = present(facts)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observedPictures.remove(key)
                guard self.listeners[key] != nil, let facts = self.fetched[key] else { return }
                let state = self.present(facts)
                self.listeners[key]?.values.forEach { $0.yield(state) }
                self.observePicture(key)
            }
        }
    }

    private func unsubscribe(_ id: UUID, from key: String) {
        listeners[key]?[id] = nil
        guard listeners[key]?.isEmpty ?? true else { return }
        listeners[key] = nil
        subscribed[key] = nil
    }

    // MARK: - Staying current -

    // Drops what is held about a cash link and asks again for it if a card is showing it.
    //
    // Forgetting is unconditional, even with nothing on screen: a claim that settles while the card
    // is scrolled away would otherwise leave "Tap to claim" in the memo for cash already collected,
    // and the next row to show that link would paint it straight from there.
    //
    // The re-ask deliberately does not clear the painted state first. A cleared card draws
    // unresolved for as long as the lookup takes, and on a 15-second cadence that is a card that
    // blinks; the answer lands over the old one instead, and an unchanged answer changes nothing.
    private func invalidateCash(entropy: String) {
        let key = LinkCard.cashKey(entropy: entropy)
        generations[key, default: 0] += 1
        memo.forget(key)

        let card = subscribed[key]
        Task { [resolver] in
            await resolver.invalidateCash(entropy: entropy)
            guard let card else { return }
            ask(card)
        }
    }

    // Re-asks for a card the moment its claim settles on this device. `receiveCashLink` names the
    // entropy on the way out, which is the only notice this app gets that a link's claim state
    // moved: the transcript behind the sheet is still drawing "Tap to claim" for cash that has just
    // been collected. Re-arms itself once per change, the way the coordinator observes its inputs.
    private func observeSettledClaims() {
        let settled = withObservationTracking {
            claims.settled
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSettledClaims() }
        }

        let news = settled.subtracting(honoredClaims)
        honoredClaims = settled
        for entropy in news {
            invalidateCash(entropy: entropy)
        }
    }

    // Re-asks for every card on screen still showing as claimable, on a fixed cadence and again on
    // foreground — where the cadence has been asleep and the answer is most likely to have moved.
    // Claimed and expired are terminal, so they are left alone: asking again spends a request on an
    // answer that cannot have changed.
    private func startClaimableRefresh() {
        claimRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.claimableRefresh))
                guard let self, !Task.isCancelled else { return }
                // A tick that lands while the app is on its way out would spend a request nobody is
                // looking at; the foreground arm asks again on the way back in.
                guard UIApplication.shared.applicationState == .active else { continue }
                refreshClaimable()
            }
        }
        foregroundTask = Task { [weak self] in
            let foregrounds = NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification)
            for await _ in foregrounds {
                guard let self, !Task.isCancelled else { return }
                refreshClaimable()
            }
        }
    }

    // Not private so a test can tick the cadence without waiting fifteen seconds for it.
    func refreshClaimable() {
        for (key, card) in subscribed {
            guard case .cash(let cash) = card else { continue }
            guard case .cash(.resolved(let resolved))? = memo.states[key] else { continue }
            guard resolved.claim == .claimable else { continue }
            invalidateCash(entropy: cash.entropy)
        }
    }
}
