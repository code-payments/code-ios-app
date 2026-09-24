//
//  ConversationLoadCoordinator.swift
//  Flipcash
//

import Foundation
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
    /// them, then the group's typists the rows leave out. The view fetches their avatars from this: the mapped rows carry only a BlurHash —
    /// thumbnail bytes must not ride in ``Inputs``, which is compared on every observation tick, nor
    /// into the app-group cache the rows are written to in the clear.
    private(set) var attributedMembers: [ConversationMember] = []

    /// The window's senders and typists that neither the chat's roster nor the local cache could
    /// name, in the order the window first shows them. The view resolves these over the network — the transcript
    /// itself never blocks on it, and a sender that lands is attributed by the next re-map.
    private(set) var unattributedSenders: [UserID] = []

    let conversationID: ConversationID

    /// Thanks the sender of a cash link the reader opens from this transcript, once it is collected.
    let claimReplies: CashLinkClaimReplies

    private let controller: ConversationController
    private let session: Session
    /// Supplies the counterpart's profile card, resolved live — it runs inside the observation
    /// scope, so whatever it reads (the contact directory, the conversation) re-triggers mapping.
    /// Nil for a chat with no counterpart to card.
    private let profileCard: @MainActor () -> ChatProfileCard?
    /// Names senders the chat's own roster leaves out, from what the device already knows about
    /// them. Observed like every other input, so a reload re-attributes the window in place.
    private let knownAuthors: KnownAuthorDirectory
    /// Where the viewer's unread messages began at open — see ``UnreadBoundary``. Resolved in
    /// `init`, which the screen runs as it appears and so before its opening task marks the chat
    /// read; never re-read for the life of this coordinator.
    private let openingUnreadBoundary: UnreadBoundary
    /// The newest stored message at open. A message of the viewer's past it is a send made on this
    /// visit, which ends the divider under ``UnreadDividerLifetime/untilSend``.
    private let newestAtOpen: MessageID?
    /// Latched on the first send of the visit, so deleting that message doesn't bring the divider
    /// back.
    @ObservationIgnored private var viewerHasSent = false
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

    /// The furthest ahead a single sleep is allowed to reach. A 48-hour delete window would
    /// otherwise park a task for two days behind a transcript nobody is reading; clamping costs at
    /// most one extra remap per hour on a transcript left open that long.
    private static let expiryHorizon: TimeInterval = 3600

    /// The most unread messages the opening window grows to include, so a chat left for weeks does
    /// not lay out its whole backlog on open.
    private static let unreadRevealLimit = 200

    init(
        conversationID: ConversationID,
        controller: ConversationController,
        session: Session,
        knownAuthors: KnownAuthorDirectory,
        profileCard: @escaping @MainActor () -> ChatProfileCard?
    ) {
        self.conversationID = conversationID
        self.controller = controller
        self.session = session
        self.knownAuthors = knownAuthors
        self.profileCard = profileCard
        self.loader = MessageLoader(conversationID: conversationID, controller: controller)
        let boundary = controller.unreadBoundary(for: conversationID)
        self.openingUnreadBoundary = boundary
        self.newestAtOpen = controller.lastConfirmedMessage(for: conversationID)?.id
        self.claimReplies = CashLinkClaimReplies(claims: session.cashLinkClaims) { [controller] messageID in
            Task { await controller.send(CashLinkClaimReplies.thanks, to: conversationID, repliedTo: messageID) }
        }

        // The divider sits under the newest message at or below the pointer, so that message has to
        // be in the window for the divider to draw. Past the limit the transcript opens at the bottom
        // as it always has, and the divider draws once the reader pages back to it.
        if case .at(let readThrough, let count) = boundary, count <= Self.unreadRevealLimit,
           let anchor = controller.newestPersistedMessageID(through: readThrough, in: conversationID) {
            loader.reveal(anchor)
        }

        // First paint is synchronous so an open never flashes an empty transcript; every later
        // change maps off the main thread.
        paint(currentInputs())
        observeInputs()
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
            self.headsHistory = inputs.headsHistory
            self.attributedMembers = attribution.members
            self.unattributedSenders = attribution.unnamed
        }
    }

    // Maps on the main thread and lands the whole result at once, rather than through `refresh`'s
    // detached hop. First paint needs that: the hop would flash an empty transcript.
    private func paint(_ inputs: Inputs) {
        let attribution = Self.attribution(in: inputs)
        lastInputs = inputs
        attributedMembers = attribution.members
        unattributedSenders = attribution.unnamed
        items = Self.map(inputs, authors: Self.authors(from: attribution.members))
        headsHistory = inputs.headsHistory
        scheduleWindowExpiry(for: inputs)
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
            // Capped here rather than in `map`, so a typist the row will never draw is neither
            // compared on every tick nor sent off to have their picture fetched.
            typists: Array(controller.typists(in: conversationID).suffix(ChatItem.maxTypingAvatars)),
            profileCard: headsHistory ? profileCard() : nil,
            branding: branding,
            conversation: conversation,
            // A chat whose record hasn't landed yet has no gate to read, so it keeps the member menu.
            isMember: conversation.map(controller.isMember(of:)) ?? true,
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
            unreadBoundary: unreadBoundary(in: window)
        )
    }

    /// The opening boundary, or `.none` once the viewer has sent a message on this visit and the
    /// lifetime ends the divider there.
    private func unreadBoundary(in window: [ConversationMessage]) -> UnreadBoundary {
        switch UnreadDividerLifetime.current {
        case .untilClose:
            return openingUnreadBoundary
        case .untilSend:
            if !viewerHasSent {
                viewerHasSent = window.contains { message in
                    guard message.isFromSelf(controller.selfUserID) else { return false }
                    guard message.status == .sent else { return true }
                    return newestAtOpen.map { message.id > $0 } ?? true
                }
            }
            return viewerHasSent ? .none : openingUnreadBoundary
        }
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
                    isMember: inputs.isMember,
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
            // Classification is pure and host-gated, and that is all mapping does with a link: the
            // card is the link's identity, and the card view looks it up for itself. So nothing
            // here touches the network, and an answer landing cannot re-diff this window.
            linkCard: { links in classifier.firstCard(in: links) },
            unreadBoundary: inputs.unreadBoundary
        )
        if !inputs.typists.isEmpty {
            // Only a group draws faces ahead of the dots; a DM's bubble stays as it was. A typist no
            // roster can name still gets a face, the placeholder one.
            let typists = inputs.namesAuthors
                ? inputs.typists.map { authors[$0] ?? ChatAuthor(id: $0, name: "") }
                : []
            items.append(.typingIndicator(typists: typists))
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
    /// The group's typists follow the window's senders, so their pictures are fetched too.
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
        for senderID in inputs.messages.compactMap(\.senderID) + inputs.typists {
            guard seen.insert(senderID).inserted else { continue }
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
        /// The other members typing, oldest first, capped at ``ChatItem/maxTypingAvatars``.
        var typists: [UserID]
        var profileCard: ChatProfileCard?
        var branding: [PublicKey: Branding]
        var conversation: Conversation?
        /// False for a non-member reading a group they have not joined, who is offered no Reply.
        var isMember: Bool
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
        /// Where the divider goes; `.none` draws none.
        var unreadBoundary: UnreadBoundary

        struct Branding: Equatable, Sendable {
            var token: String
            var iconURL: URL?
        }
    }
}
