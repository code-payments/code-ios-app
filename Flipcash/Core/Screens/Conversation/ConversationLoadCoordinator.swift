//
//  ConversationLoadCoordinator.swift
//  Flipcash
//

import Foundation
import UIKit
import FlipcashCore
import FlipcashUI

/// Owns a conversation's `MessageLoader` and turns its window into display-ready `[ChatItem]`.
/// It observes exactly the inputs the mapping consumes, maps them off the main thread, and lands
/// the result as immutable `items`; the view reads only `items`, never raw messages. An unrelated
/// observable tick (a typing heartbeat, another conversation's event) leaves the inputs unchanged
/// and does no work.
@MainActor @Observable
final class ConversationLoadCoordinator {

    let loader: MessageLoader

    /// The rendered transcript, produced off the main thread and landed here as immutable state.
    private(set) var items: [ChatItem] = []

    /// Whether ``items`` is the whole locally-known history, and so carries the transcript's head
    /// card. Landed with `items` rather than read from the loader, so a view that draws its own
    /// head card (a group's) turns it on and off in step with the rows it sits above.
    private(set) var headsHistory = false

    /// The people the landed transcript attributes its rows to, in the order the window first shows
    /// them. The view fetches their avatars from this: the mapped rows carry only a BlurHash —
    /// thumbnail bytes must not ride in ``Inputs``, which is compared on every observation tick, nor
    /// into the app-group cache the rows are written to in the clear.
    private(set) var attributedMembers: [ConversationMember] = []

    /// The window's senders that neither the chat's roster nor the local cache could name, in the
    /// order the window first shows them. The view resolves these over the network — the transcript
    /// itself never blocks on it, and a sender that lands is attributed by the next re-map.
    private(set) var unattributedSenders: [UserID] = []

    let conversationID: ConversationID
    private let controller: ConversationController
    private let session: Session
    /// Supplies the counterpart's profile card, resolved live — it runs inside the observation
    /// scope, so whatever it reads (the contact directory, the conversation) re-triggers mapping.
    /// Nil for a chat with no counterpart to card.
    private let profileCard: @MainActor () -> ChatProfileCard?
    /// Names senders the chat's own roster leaves out, from what the device already knows about
    /// them. Observed like every other input, so a reload re-attributes the window in place.
    private let knownAuthors: KnownAuthorDirectory
    /// Fills a link card in. Read-only by construction — see ``LinkCardResolver``.
    private let linkCards: LinkCardResolver
    /// The answers already in hand, so first paint draws them — see ``LinkCardMemo``.
    private let cardMemo: LinkCardMemo

    /// What the resolver has answered so far, keyed the way it memoizes. Carried into `Inputs` so
    /// mapping stays pure, and observation-ignored for the same reason `capabilityClock` is: the
    /// resolution task advances it and re-maps explicitly, rather than through the observation arm.
    ///
    /// Seeded from ``LinkCardMemo`` rather than starting empty, so a chat opened again paints the
    /// cards it already has answers for instead of flashing them unresolved for a hop.
    @ObservationIgnored private var cardStates: [String: LinkCard.State] = [:]
    /// Lookups already in flight, so a re-map mid-resolution does not ask a second time.
    @ObservationIgnored private var cardsInFlight: Set<String> = []
    /// Settled claims already acted on, so the log — which only grows — is read as the news in it.
    @ObservationIgnored private var honoredClaims: Set<String> = []
    @ObservationIgnored private var claimRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var foregroundTask: Task<Void, Never>?

    @ObservationIgnored private var lastInputs: Inputs?
    @ObservationIgnored private var mapTask: Task<Void, Never>?

    /// The clock capability resolution reads. It advances only when a window actually lapses, never
    /// on every observation tick — see ``scheduleWindowExpiry(for:)``.
    @ObservationIgnored private var capabilityClock: Date = .now
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    /// Fire a beat after the deadline, not on it. The window boundary is inclusive, so a timer that
    /// landed exactly on `date + window` would still resolve the capability as granted and then
    /// compute the same deadline again, and the row would never drop.
    private static let expiryGrace: TimeInterval = 1

    /// How often a card the reader can still act on asks again, while they are looking at it. A
    /// link claimed on someone else's device sends nothing here, so a claimable card is only ever
    /// as fresh as the last ask; Android re-asks on the same cadence.
    private static let claimableRefresh: TimeInterval = 15

    /// The furthest ahead a single sleep is allowed to reach. A 48-hour delete window would
    /// otherwise park a task for two days behind a transcript nobody is reading; clamping costs at
    /// most one extra remap per hour on a transcript left open that long.
    private static let expiryHorizon: TimeInterval = 3600

    init(
        conversationID: ConversationID,
        controller: ConversationController,
        session: Session,
        knownAuthors: KnownAuthorDirectory,
        linkCards: LinkCardResolver,
        linkCardMemo: LinkCardMemo,
        profileCard: @escaping @MainActor () -> ChatProfileCard?
    ) {
        self.conversationID = conversationID
        self.controller = controller
        self.session = session
        self.knownAuthors = knownAuthors
        self.linkCards = linkCards
        self.cardMemo = linkCardMemo
        self.cardStates = linkCardMemo.states
        self.profileCard = profileCard
        self.loader = MessageLoader(conversationID: conversationID, controller: controller)

        // First paint is synchronous so an open never flashes an empty transcript; every later
        // change maps off the main thread.
        let initial = currentInputs()
        let initialAttribution = Self.attribution(in: initial)
        self.lastInputs = initial
        self.attributedMembers = initialAttribution.members
        self.unattributedSenders = initialAttribution.unnamed
        self.items = Self.map(initial, authors: Self.authors(from: initialAttribution.members))
        self.headsHistory = initial.headsHistory
        scheduleWindowExpiry(for: initial)
        resolveCards(in: items)
        observeInputs()
        observeSettledClaims()
        startClaimableRefresh()
    }

    isolated deinit {
        claimRefreshTask?.cancel()
        foregroundTask?.cancel()
    }

    /// The reader reached the top — reveal older history.
    func reachedTop() { loader.loadOlder() }

    /// The counterpart's display name as the last mapping resolved it. The composer's reply strip
    /// reads this so the strip and the sent bubble's quote name the same person the same way.
    var counterpartName: String { lastInputs?.counterpartName ?? "" }

    /// The name the landed transcript attributes `senderID`'s rows to, or nil when neither the
    /// chat's roster nor the local cache can name them. The composer's reply strip resolves through
    /// this so it names the same person the quoted bubble does.
    func attributedName(for senderID: UserID) -> String? {
        let name = attributedMembers.first { $0.userID == senderID }?.displayName
        return (name?.isEmpty ?? true) ? nil : name
    }

    // Tracks exactly the inputs `map` reads; on the next change to any of them it re-maps off the
    // main thread and re-arms. An unchanged input set short-circuits before spawning any work.
    private func observeInputs() {
        let inputs = withObservationTracking {
            currentInputs()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeInputs() }
        }
        refresh(with: inputs)
    }

    // Re-maps off the main thread when the inputs actually changed, and re-arms the expiry timer
    // for whatever the new set implies. Separate from `observeInputs` because the expiry timer
    // drives a re-map too, and it must not install a second observation arm to do it.
    private func refresh(with inputs: Inputs) {
        guard inputs != lastInputs else { return }
        lastInputs = inputs
        scheduleWindowExpiry(for: inputs)
        // Resolved here rather than inside the mapping so the view can read the same roster the
        // rows were attributed from, and so the resolution runs once per change rather than twice.
        let attribution = Self.attribution(in: inputs)
        let authors = Self.authors(from: attribution.members)
        mapTask?.cancel()
        mapTask = Task { [weak self] in
            let mapped = await Task.detached { Self.map(inputs, authors: authors) }.value
            guard let self, !Task.isCancelled else { return }
            self.items = mapped
            self.resolveCards(in: mapped)
            self.headsHistory = inputs.headsHistory
            self.attributedMembers = attribution.members
            self.unattributedSenders = attribution.unnamed
        }
    }

    // Asks the resolver for every card the landed transcript still shows unresolved, then re-maps
    // so the answers land in place. The first pass renders unresolved cards and the second fills
    // them in — the spec calls the unresolved card the floor rather than a failure, so there is no
    // spinner and the two passes lay out identically. A lookup that fails leaves the card where it
    // is, and is recorded all the same so a scrolling transcript does not retry it on every tick.
    private func resolveCards(in items: [ChatItem]) {
        var pending: [LinkCard] = []
        var seen: Set<String> = []
        for case .message(let message) in items {
            guard let card = message.linkPreview?.card, card.isUnresolved else { continue }
            let key = card.resolutionKey
            guard cardStates[key] == nil, !cardsInFlight.contains(key), seen.insert(key).inserted else { continue }
            pending.append(card)
        }
        guard !pending.isEmpty else { return }

        cardsInFlight.formUnion(seen)
        Task { [weak self, linkCards] in
            await Self.land(pending, through: linkCards) { [weak self] key, state in
                self?.landCardState(state, for: key)
            }
        }
    }

    // One query per card, all of them at once, and each answer drawn the moment it arrives.
    //
    // Both halves matter. Asking in sequence made a transcript's cards wait on each other, so the
    // last card stayed blank for the sum of every lookup ahead of it; landing the batch in one go
    // then held every answer hostage to the slowest of them. Android issues its queries the same
    // way, one `async` each, and reads them back per card.
    //
    // A failed lookup comes back unresolved and is landed like any other answer — that is what
    // stops a scrolling transcript from asking again on every tick.
    static func land(
        _ cards: [LinkCard],
        through resolver: LinkCardResolver,
        onAnswer: @escaping @MainActor (String, LinkCard.State) -> Void
    ) async {
        await withTaskGroup(of: (String, LinkCard.State).self) { group in
            for card in cards {
                group.addTask { (card.resolutionKey, await resolver.resolve(card).state) }
            }
            for await (key, state) in group {
                await onAnswer(key, state)
            }
        }
    }

    // Where every answer lands, whichever asked for it: into the working copy the mapping reads,
    // into the container's memo so the next open of this chat starts from it, and then a re-map.
    private func landCardState(_ state: LinkCard.State, for key: String) {
        cardsInFlight.remove(key)
        cardStates[key] = state
        cardMemo.record(state, for: key)
        refresh(with: currentInputs())
    }

    // Re-asks for a card the moment its claim settles on this device. `receiveCashLink` names the
    // entropy on the way out, which is the only notice this app gets that a link's claim state
    // moved: the transcript behind the sheet is still drawing "Tap to claim" for cash that has just
    // been collected. Tracks the log rather than folding it into `Inputs`, which is the set `map`
    // reads, and re-arms itself once per change the way `observeInputs` does.
    private func observeSettledClaims() {
        let settled = withObservationTracking {
            session.cashLinkClaims.settled
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSettledClaims() }
        }

        let news = settled.subtracting(honoredClaims)
        honoredClaims = settled
        guard !news.isEmpty else { return }
        let cards = cashCards { news.contains($0.entropy) }
        guard !cards.isEmpty else { return }
        Task { await self.reresolveCash(cards) }
    }

    // Re-asks for every card the transcript still shows as claimable, on a fixed cadence and again
    // on foreground — where the cadence has been asleep and the answer is most likely to have moved.
    // Claimed and expired are terminal, so they are left alone: asking again spends a request on an
    // answer that cannot have changed.
    private func startClaimableRefresh() {
        claimRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.claimableRefresh))
                guard let self, !Task.isCancelled else { return }
                await self.refreshClaimableCards()
            }
        }
        foregroundTask = Task { [weak self] in
            let foregrounds = NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification)
            for await _ in foregrounds {
                guard let self, !Task.isCancelled else { return }
                await self.refreshClaimableCards()
            }
        }
    }

    private func refreshClaimableCards() async {
        // A tick that lands while the app is on its way out would spend a request nobody is looking
        // at; the foreground arm asks again on the way back in.
        guard UIApplication.shared.applicationState == .active else { return }
        await reresolveCash(cashCards { cash in
            guard case .resolved(let resolved) = cash.state else { return false }
            return resolved.claim == .claimable
        })
    }

    // Drops what the resolver memoized for these links and asks again, landing each answer over the
    // old one rather than clearing it first: a cleared state draws the card unresolved for as long
    // as the lookup takes, and on a 15-second cadence that is a card that blinks. An answer that
    // comes back unchanged leaves `Inputs` equal, so nothing re-maps at all.
    private func reresolveCash(_ cards: [LinkCard.Cash]) async {
        let pending = cards.filter { !cardsInFlight.contains(LinkCard.cash($0).resolutionKey) }
        guard !pending.isEmpty else { return }

        cardsInFlight.formUnion(pending.map { LinkCard.cash($0).resolutionKey })

        for cash in pending {
            await linkCards.invalidateCash(entropy: cash.entropy)
        }
        await Self.land(pending.map { LinkCard.cash($0) }, through: linkCards) { [weak self] key, state in
            self?.landCardState(state, for: key)
        }
    }

    // The cash cards the landed transcript draws, one per link — the same link quoted twice is one
    // lookup, the way `resolveCards` treats it.
    private func cashCards(where include: (LinkCard.Cash) -> Bool) -> [LinkCard.Cash] {
        var cards: [LinkCard.Cash] = []
        var seen: Set<String> = []
        for case .message(let message) in items {
            guard case .cash(let cash)? = message.linkPreview?.card, include(cash) else { continue }
            guard seen.insert(cash.entropy).inserted else { continue }
            cards.append(cash)
        }
        return cards
    }

    // Wakes once, at the next instant a message loses Edit or Delete, and advances `capabilityClock`
    // so the re-map resolves against a real clock. Nothing polls: with no expiring message in the
    // window there is no timer at all, and each firing schedules only the next deadline.
    private func scheduleWindowExpiry(for inputs: Inputs) {
        expiryTask?.cancel()
        let now = Date.now
        guard let deadline = MessageCapability.nextExpiry(
            among: inputs.messages,
            in: inputs.conversation,
            as: inputs.selfUserID,
            policy: inputs.policy,
            now: now
        ) else { return }

        let wake = min(deadline.addingTimeInterval(Self.expiryGrace), now.addingTimeInterval(Self.expiryHorizon))
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, wake.timeIntervalSince(now))))
            guard !Task.isCancelled, let self else { return }
            self.capabilityClock = .now
            self.refresh(with: self.currentInputs())
        }
    }

    private func currentInputs() -> Inputs {
        let conversation = controller.conversation(withID: conversationID)
        // A group has no single counterpart to have read anything — `counterpartReadReceipt` picks
        // an arbitrary member — so the receipt stays at "Delivered" there, which is what the design
        // shows (node 10125:19256). Group read state is an N-member problem and not this pass.
        let namesAuthors = conversation?.type == .group
        let read = namesAuthors ? nil : conversation?.counterpartReadReceipt(excluding: controller.selfUserID)
        let window = loader.messages
        var branding: [PublicKey: Inputs.Branding] = [:]
        for message in window {
            guard case .cash(let fiat) = message.content, branding[fiat.mint] == nil else { continue }
            if let balance = session.balance(for: fiat.mint) {
                branding[fiat.mint] = .init(token: balance.name, iconURL: balance.imageURL)
            }
        }
        let counterpartName = conversation?.counterpart(excluding: controller.selfUserID)?.displayName ?? ""
        // The head card belongs only above a short transcript — a long or paged history drops it,
        // and the nav title opens the same place it would.
        let headsHistory = loader.isEntireHistory(windowCount: window.count)
        // The window first — a reply to a nearby message resolves with no database read at all —
        // then the table, for a reply pointing above the window. Nothing pages the server: a quote
        // whose original was never fetched renders as unavailable, by design.
        var quotedMessages: [UInt64: ConversationMessage] = [:]
        // Indexed rather than searched: this runs on every observation tick, and a linear scan per
        // reply is quadratic in the window, which a long group transcript feels as scroll jank.
        var byID: [UInt64: ConversationMessage] = [:]
        for message in window {
            byID[message.id.value] = message
        }
        for message in window {
            guard let repliedTo = message.repliedTo, quotedMessages[repliedTo.value] == nil else { continue }
            if let inWindow = byID[repliedTo.value] {
                quotedMessages[repliedTo.value] = inWindow
            } else if let persisted = controller.persistedMessage(repliedTo, in: conversationID) {
                quotedMessages[repliedTo.value] = persisted
            }
        }
        return Inputs(
            messages: window,
            selfUserID: controller.selfUserID,
            counterpartPointer: read?.pointer,
            counterpartReadDate: read?.date,
            suppressReceiptFor: controller.settlingSendID,
            isTyping: controller.isCounterpartTyping(in: conversationID),
            profileCard: headsHistory ? profileCard() : nil,
            branding: branding,
            conversation: conversation,
            counterpartName: counterpartName,
            quotedMessages: quotedMessages,
            // Read live, so the windows take effect on the same re-map that lands the flags fetch.
            policy: MessagePolicy(userFlags: session.userFlags),
            now: capabilityClock,
            namesAuthors: namesAuthors,
            // Only a transcript that attributes its rows has anything to resolve, so a DM never
            // takes a dependency on the directory and never re-maps when it reloads.
            knownAuthors: namesAuthors ? knownAuthors.snapshot : .empty,
            headsHistory: headsHistory,
            cardStates: cardStates
        )
    }

    nonisolated private static func map(_ inputs: Inputs, authors: [UserID: ChatAuthor]) -> [ChatItem] {
        let classifier = LinkCardClassifier()
        var items = ChatItem.from(
            inputs.messages,
            selfUserID: inputs.selfUserID,
            counterpartRead: inputs.counterpartPointer.map { (pointer: $0, date: inputs.counterpartReadDate) },
            suppressReceiptFor: inputs.suppressReceiptFor,
            cashBranding: { fiat in
                guard let branding = inputs.branding[fiat.mint] else { return ("Cash", nil) }
                return (branding.token, branding.iconURL)
            },
            deletedPresentation: inputs.policy.deletedPresentation,
            // `now` is carried in `Inputs` rather than read here, which keeps `map` pure and keeps
            // the equality short-circuit meaningful: an unrelated tick sees the same clock and does
            // no work. The price is that the clock is only as fresh as whatever last advanced it,
            // so `scheduleWindowExpiry` owns that — it wakes at each window's expiry, sets the
            // clock, and re-maps. Between those wakes no capability boundary can have been crossed.
            capabilities: { message in
                MessageCapability.resolve(
                    for: message,
                    in: inputs.conversation,
                    as: inputs.selfUserID,
                    policy: inputs.policy,
                    now: inputs.now
                )
            },
            counterpartName: inputs.counterpartName,
            quotedMessage: { inputs.quotedMessages[$0.value] },
            // A sender neither the chat nor the local cache can name gets no author, so the row
            // draws as it does in a DM rather than under a blank name.
            author: { message in message.senderID.flatMap { authors[$0] } },
            namesAuthors: inputs.namesAuthors,
            // Classification is pure and host-gated; the state comes from whatever the resolver has
            // already answered. Nothing here touches the network — a card that has not resolved yet
            // renders unresolved and `resolveCards` asks for it once the rows have landed.
            linkCard: { links in
                classifier.firstCard(in: links)?.applying(inputs.cardStates)
            }
        )
        if inputs.isTyping {
            items.append(.typingIndicator)
        }
        if let card = inputs.profileCard {
            items.insert(.profileCard(card), at: 0)
        }
        return items
    }

    /// Who the window's senders are, resolved for the window only rather than for the whole
    /// directory — the local cache can name far more people than any one transcript shows.
    ///
    /// The chat's own roster wins: it is the identity that chat published for the member, which is
    /// what the transcript is attributing. Everyone it leaves out — the subset a large group embeds
    /// leaves plenty — falls through to whatever the device knows about them from elsewhere. The
    /// senders neither source covers come back in `unnamed`, for the view to fetch.
    /// Both are empty for every transcript that does not attribute its rows.
    nonisolated private static func attribution(in inputs: Inputs) -> (members: [ConversationMember], unnamed: [UserID]) {
        guard inputs.namesAuthors else { return ([], []) }

        var roster: [UserID: ConversationMember] = [:]
        for member in inputs.conversation?.members ?? [] {
            guard let userID = member.userID, roster[userID] == nil else { continue }
            roster[userID] = member
        }

        var seen: Set<UserID> = []
        var members: [ConversationMember] = []
        var unnamed: [UserID] = []
        for message in inputs.messages {
            guard let senderID = message.senderID, seen.insert(senderID).inserted else { continue }
            // The viewer's own rows are never attributed, so their id is not worth a round trip.
            guard senderID != inputs.selfUserID else { continue }
            guard let member = roster[senderID] ?? inputs.knownAuthors.membersByUserID[senderID] else {
                unnamed.append(senderID)
                continue
            }
            // A roster row with no name attributes nothing, so it is a gap like an absent one —
            // the profile fetch is what can still fill it.
            if member.displayName.isEmpty {
                unnamed.append(senderID)
            }
            members.append(member)
        }
        return (members, unnamed)
    }

    /// The name and BlurHash each row draws, keyed by the sender it belongs to.
    nonisolated private static func authors(from members: [ConversationMember]) -> [UserID: ChatAuthor] {
        var authors: [UserID: ChatAuthor] = [:]
        for member in members {
            guard let userID = member.userID else { continue }
            authors[userID] = ChatAuthor(
                id: userID,
                name: member.displayName,
                blurhash: member.profilePicture?.thumbnailBlurhash
            )
        }
        return authors
    }

    /// Everything `map` reads, captured by value so an unchanged set short-circuits the remap and
    /// the snapshot can cross to a background task. Cash branding is pre-resolved per mint so a
    /// branding change participates.
    struct Inputs: Equatable, Sendable {
        var messages: [ConversationMessage]
        var selfUserID: UserID
        var counterpartPointer: MessageID?
        var counterpartReadDate: Date?
        var suppressReceiptFor: String?
        var isTyping: Bool
        var profileCard: ChatProfileCard?
        var branding: [PublicKey: Branding]
        var conversation: Conversation?
        /// The counterpart's display name, for a quote whose original they wrote.
        var counterpartName: String
        /// Every message quoted by a reply in the window, pre-resolved so `map` stays pure. Keyed
        /// by raw id because `MessageID` is the natural key and the dictionary must be `Equatable`.
        var quotedMessages: [UInt64: ConversationMessage]
        var policy: MessagePolicy
        /// The clock capabilities resolve against; advanced only at a window's expiry.
        var now: Date
        /// Whether the transcript attributes its rows: true for a group chat, false for a DM,
        /// where every row is one of two people and a name above each would be noise.
        var namesAuthors: Bool
        /// Identities for senders the chat's own roster leaves out. Compared by identity — see
        /// ``KnownAuthorDirectory/Snapshot``.
        var knownAuthors: KnownAuthorDirectory.Snapshot
        /// Whether the window is the whole locally-known history — see ``headsHistory``.
        var headsHistory: Bool
        /// What the resolver has answered about the window's link cards, keyed by link identity.
        /// Part of the input set, so an answer landing re-maps the transcript in place.
        var cardStates: [String: LinkCard.State]

        struct Branding: Equatable, Sendable {
            var token: String
            var iconURL: URL?
        }
    }
}
