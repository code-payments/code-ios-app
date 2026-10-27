//
//  ReactionAlertController.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import UIKit
#if DEBUG
import notify
#endif
import FlipcashCore
import FlipcashUI

nonisolated private let logger = Logger(label: "flipcash.reaction-alerts")

/// Turns reaction updates on the user's own messages into the in-app pill.
///
/// The decisions are the pure functions in `ReactionAlert.swift`; this owns what they need from
/// the app: the clock-free queue, the local database and `GetMessage` for the sender, names, the
/// open chat, and the pill itself. Nothing is stored or replayed, so an update that arrives while
/// the app is away is lost, which the spec accepts.
@MainActor
final class ReactionAlertController {

    private let pill: AlertPillController
    private let selfUserID: UserID
    private weak var conversations: ConversationController?

    private var boosts = ActorBoostTracker()
    private var queue = ReactionAlertQueue()
    nonisolated(unsafe) private var resignObserver: NSObjectProtocol?

    /// Whether the app is in front. Replaceable so a test can drive it.
    var isForeground: () -> Bool = { UIApplication.shared.applicationState == .active }

    /// Whether a pill may draw now; false under a sheet or dialog.
    var canPresent: () -> Bool = { true }

    /// The display currency amounts are shown in.
    var displayCurrency: () -> DisplayCurrency = { DisplayCurrency(currency: .usd, rates: [:]) }

    /// Names a user the chat's own roster leaves out, fetching their profile when nothing on the
    /// device has a name for them. A large group embeds only part of its roster.
    var knownName: (UserID) async -> String? = { _ in nil }
    /// The reactor's profile photo, loading it first if it isn't cached. Nil when they have none.
    var avatarData: (UserID) async -> Data? = { _ in nil }
    /// Photos fetched for reactors in the current alert, keyed by user.
    private var avatarDataByActor: [UserID: Data] = [:]

    /// Opens a chat at a message, for a pill tapped anywhere else.
    var openMessage: (ConversationID, MessageID) -> Void = { _, _ in }

    init(pill: AlertPillController, selfUserID: UserID, conversations: ConversationController) {
        self.pill = pill
        self.selfUserID = selfUserID
        self.conversations = conversations
        pill.onFinished = { [weak self] _ in self?.pillFinished() }
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset() }
        }
        #if DEBUG
        registerDebugTriggers()
        #endif
    }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    /// Drops the pill and everything waiting, for the app leaving the foreground or a sign-out.
    func reset() {
        queue.removeAll()
        pill.cancel()
    }

    /// Clears a chat's pills for the chat being opened: drops the ones waiting, then closes the one
    /// on screen if it is that chat's, which promotes the next.
    func conversationOpened(_ conversationID: ConversationID) {
        queue.removeWaiting(for: conversationID)
        if queue.current?.conversationID == conversationID {
            pill.cancel()
        }
    }

    // MARK: - Updates -

    /// Considers each update of one stream event, in order.
    func handle(_ updates: [DecodedReactionUpdate], in conversationID: ConversationID) {
        // The boost delta needs every boost seen, qualifying or not, so it is recorded before any
        // rule can drop the update.
        var deltas: [DecodedReactionUpdate: UInt64] = [:]
        for update in updates where update.boosted {
            deltas[update] = boosts.recordBoost(update, newTotalCents: ReactionBoost.cents(usd: update.actorBoostUSD))
        }
        let candidates = updates.filter {
            ReactionAlertTrigger.precheck($0, selfUserID: selfUserID, isForeground: isForeground()) == nil
        }
        guard !candidates.isEmpty else { return }
        Task { [weak self] in
            for update in candidates {
                await self?.consider(update, delta: deltas[update] ?? 0, in: conversationID)
            }
        }
    }

    private func consider(_ update: DecodedReactionUpdate, delta: UInt64, in conversationID: ConversationID) async {
        guard let conversations else { return }
        guard let message = await sender(of: update.messageID, in: conversationID, using: conversations) else { return }
        guard ReactionAlertTrigger.checkSender(message.senderID, selfUserID: selfUserID) == nil else { return }
        // The app may have gone away while the lookup ran.
        guard isForeground(), canPresent() else { return }

        let placement = ReactionAlertPlacement.decide(
            alertConversation: conversationID,
            openConversation: conversations.visibleConversationID
        )
        let topRow: String
        switch placement {
        case .bubbleOnly: return
        case .pill(.chatName): topRow = conversations.displayName(forConversationID: conversationID)
        }

        let isBoost = update.boosted && delta > 0
        let event = ReactionAlertEvent(
            conversationID: conversationID,
            messageID: update.messageID,
            emoji: update.emoji,
            actor: update.actor,
            actorName: await actorName(update.actor, in: conversationID, using: conversations),
            isBoost: isBoost,
            boostDeltaCents: isBoost ? delta : 0,
            snippet: Self.snippet(for: message, display: displayCurrency()),
            topRow: topRow
        )
        if avatarDataByActor[update.actor] == nil, let data = await avatarData(update.actor) {
            avatarDataByActor[update.actor] = data
        }
        switch queue.enqueue(event) {
        case .started, .merged: present()
        case .queued: break
        }
    }

    /// The message from the local copy, else from the server. Nil when neither can say who sent it.
    private func sender(of messageID: MessageID, in conversationID: ConversationID, using conversations: ConversationController) async -> ConversationMessage? {
        if let local = try? conversations.database.message(id: messageID, conversationID: conversationID), local.senderID != nil {
            return local
        }
        do {
            return try await conversations.messaging.getMessage(
                owner: conversations.owner, conversationID: conversationID, messageID: messageID, viewMode: .full
            )
        } catch {
            logger.info("Dropped reaction alert: sender lookup failed", metadata: [
                "conversationID": "\(conversationID)",
                "error": "\(error)",
            ])
            return nil
        }
    }

    private func actorName(_ actor: UserID, in conversationID: ConversationID, using conversations: ConversationController) async -> String {
        guard let conversation = conversations.conversation(withID: conversationID) else { return "Someone" }
        if let name = conversation.members.first(where: { $0.userID == actor })?.displayName, !name.isEmpty {
            return name
        }
        guard conversation.type == .group else { return conversations.displayName(for: conversation) }
        if let name = await knownName(actor), !name.isEmpty {
            return name
        }
        return "Someone"
    }

    // MARK: - Pill -

    private func present() {
        guard let current = queue.current else { return }
        guard canPresent() else {
            reset()
            return
        }
        let display = displayCurrency()
        let actors = current.actors
        let avatars = actors.map {
            AlertPillContent.Avatar(
                initial: String($0.actorName.first ?? "?").uppercased(),
                seed: $0.actorName.hashValue,
                imageData: avatarDataByActor[$0.actor]
            )
        }
        let trailing: AlertPillContent.Trailing
        if let cents = current.boostCents {
            trailing = .amount("+" + display.amount(FiatAmount.usd(Decimal(cents) / 100)).formatted())
        } else if current.isStacked {
            trailing = .emojis(current.emojis)
        } else {
            trailing = .emoji(current.latest.emoji)
        }
        let conversationID = current.conversationID
        let messageID = current.messageID
        pill.present(
            AlertPillContent(
                topRow: current.topRow,
                title: current.title,
                subtitle: current.subtitle,
                trailing: trailing,
                avatars: avatars
            ),
            hold: current.hold,
            haptic: current.latest.isBoost ? .success : .light
        ) { [weak self] in
            self?.tapped(conversationID: conversationID, messageID: messageID)
        }
    }

    private func tapped(conversationID: ConversationID, messageID: MessageID) {
        openMessage(conversationID, messageID)
    }

    private func pillFinished() {
        guard queue.advance() != nil else { return }
        present()
    }

    #if DEBUG
    // MARK: - Debug triggers -

    /// Fires canned alerts so the banner can be recorded without a second account:
    /// `xcrun simctl spawn <udid> notifyutil -p flipcash.debug.alert.reaction` (also `.boost`, `.stack`).
    private var debugTokens: [Int32] = []
    private var debugStack = 0

    private func registerDebugTriggers() {
        for kind in ["reaction", "boost", "stack"] {
            var token: Int32 = 0
            notify_register_dispatch("flipcash.debug.alert.\(kind)", &token, .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fireDebugAlert(kind) }
            }
            debugTokens.append(token)
        }
    }

    private func fireDebugAlert(_ kind: String) {
        let quote = "Sorry for the delay! 2026.10.3 dropped this morning"
        let content: AlertPillContent
        switch kind {
        case "boost":
            debugStack = 0
            content = AlertPillContent(
                topRow: "🚀 Release Central", title: "Chloe boosted their 🔥", subtitle: quote,
                trailing: .amount("+$5.00"), avatars: [.init(initial: "C", seed: 3)]
            )
        case "stack":
            debugStack += 1
            let names = ["Chloe", "Sam", "Ana", "Ted"]
            let emojis = ["🔥", "❤️", "🎉", "👍"]
            let count = min(debugStack + 1, names.count)
            content = AlertPillContent(
                topRow: "🚀 Release Central",
                title: count == 1 ? "Chloe reacted to your message" : "Chloe and \(count - 1) other\(count == 2 ? "" : "s") reacted",
                subtitle: quote,
                trailing: count == 1 ? .emoji("🔥") : .emojis(Array(emojis.prefix(min(count, 3)))),
                avatars: names.prefix(count).enumerated().map { .init(initial: String($1.first!), seed: $0 + 3) }
            )
        default:
            debugStack = 0
            // A real member, so the photo goes through the same lookup a live reaction uses.
            Task { await fireDebugReactionFromRealMember(quote: quote) }
            return
        }
        pill.present(content, hold: kind == "boost" ? .seconds(3.5) : .seconds(2.5), haptic: kind == "boost" ? .success : .light) {}
    }

    private func fireDebugReactionFromRealMember(quote: String) async {
        let member = conversations?.conversations.lazy.flatMap(\.members).first { $0.displayName == "XCTests" }
        let name = member?.displayName ?? "XCTests"
        var data: Data?
        if let userID = member?.userID { data = await avatarData(userID) }
        let content = AlertPillContent(
            topRow: "🚀 Release Central", title: "\(name) reacted to your message", subtitle: quote,
            trailing: .emoji("❤️"), avatars: [.init(initial: "X", seed: 1, imageData: data)]
        )
        pill.present(content, hold: .seconds(2.5), haptic: .light) {}
    }
    #endif

    // MARK: - Snippet -

    /// The quoted line under the title, in the words the reply quote uses.
    static func snippet(for message: ConversationMessage, display: DisplayCurrency) -> String {
        switch message.content {
        case .text(let text): ChatQuote.snippet(forText: text)
        case .cash(let fiat): display.amount(fiat).formatted()
        case .media(_, let caption): ChatQuote.snippet(forText: ChatMediaStrings.quoteSnippet(caption: caption))
        case .deleted: ChatQuote.deletedSnippet
        case .widget(.shareProfile): ChatQuote.sharedProfileSnippet
        case .widget(.paymentRequest): ChatQuote.paymentRequestSnippet
        case .encrypted, .widget(.unrecognized), .system: ChatQuote.unavailableSnippet
        }
    }
}
