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

    let conversationID: ConversationID
    private let controller: ConversationController
    private let session: Session
    /// Supplies the counterpart's profile card, resolved live — it runs inside the observation
    /// scope, so whatever it reads (the contact directory, the conversation) re-triggers mapping.
    private let profileCard: @MainActor () -> ChatProfileCard

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

    init(
        conversationID: ConversationID,
        controller: ConversationController,
        session: Session,
        profileCard: @escaping @MainActor () -> ChatProfileCard
    ) {
        self.conversationID = conversationID
        self.controller = controller
        self.session = session
        self.profileCard = profileCard
        self.loader = MessageLoader(conversationID: conversationID, controller: controller)

        // First paint is synchronous so an open never flashes an empty transcript; every later
        // change maps off the main thread.
        let initial = currentInputs()
        self.lastInputs = initial
        self.items = Self.map(initial)
        scheduleWindowExpiry(for: initial)
        observeInputs()
    }

    /// The reader reached the top — reveal older history.
    func reachedTop() { loader.loadOlder() }

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
        mapTask?.cancel()
        mapTask = Task { [weak self] in
            let mapped = await Task.detached { Self.map(inputs) }.value
            guard let self, !Task.isCancelled else { return }
            self.items = mapped
        }
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
        let read = conversation?.counterpartReadReceipt(excluding: controller.selfUserID)
        let window = loader.messages
        var branding: [PublicKey: Inputs.Branding] = [:]
        for message in window {
            guard case .cash(let fiat) = message.content, branding[fiat.mint] == nil else { continue }
            if let balance = session.balance(for: fiat.mint) {
                branding[fiat.mint] = .init(token: balance.name, iconURL: balance.imageURL)
            }
        }
        return Inputs(
            messages: window,
            selfUserID: controller.selfUserID,
            counterpartPointer: read?.pointer,
            counterpartReadDate: read?.date,
            suppressReceiptFor: controller.settlingSendID,
            isTyping: controller.isCounterpartTyping(in: conversationID),
            // The card heads only a short transcript — long or paged histories drop it; the
            // nav title opens the same contact card.
            profileCard: loader.isEntireHistory(windowCount: window.count) ? profileCard() : nil,
            branding: branding,
            conversation: conversation,
            // Read live, so the windows take effect on the same re-map that lands the flags fetch.
            policy: MessagePolicy(userFlags: session.userFlags),
            now: capabilityClock
        )
    }

    nonisolated private static func map(_ inputs: Inputs) -> [ChatItem] {
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
        var policy: MessagePolicy
        /// The clock capabilities resolve against; advanced only at a window's expiry.
        var now: Date

        struct Branding: Equatable, Sendable {
            var token: String
            var iconURL: URL?
        }
    }
}
