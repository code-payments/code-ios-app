//
//  ChatCashBillController.swift
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

nonisolated private let logger = Logger(label: "flipcash.chat-cash-bill")

/// The open chat's keyboard, which a bill lowers and gives back.
@MainActor
protocol ChatComposerKeyboard: AnyObject {
    var isUp: Bool { get }
    func lower()
    func raise()
}

/// The open chat screen's keyboard, reached through its view controller.
@MainActor
final class ChatKeyboardHandle: ChatComposerKeyboard {
    weak var screen: ChatScreenViewController?

    var isUp: Bool { screen?.composerHoldsKeyboard ?? false }
    func lower() { screen?.dismissKeyboard() }
    func raise() { screen?.focusComposer() }
}

/// Shows the received bill over the open chat when cash to the user lands on the live stream.
///
/// The decision is `ChatCashBill.billAmount(for:in:)`. This owns what surrounds it: waiting for
/// the verified state the bill's give operation needs, keeping a second payment out while the first
/// is being prepared or shown, and handing the keyboard back when the bill closes.
@MainActor
final class ChatCashBillController {

    /// Where a chat bill is in its life. Only one exists at a time.
    private enum Phase: Equatable {
        case idle
        /// Waiting on verified state for `messageID`; the bill is not up yet.
        case preparing(messageID: MessageID)
        /// The bill is up; `restoreKeyboard` is whether the composer held the keyboard when it came.
        case showing(restoreKeyboard: Bool)
    }

    private let selfUserID: UserID

    var isEnabled: () -> Bool = { BetaFlags.shared.hasEnabled(.chatCashBill) }
    /// The conversation on screen in the foreground.
    var openConversationID: () -> ConversationID? = { nil }
    /// A sheet, media viewer, dialog or other bill is over the chat, or the chat is in a sheet.
    var somethingOnTop: () -> Bool = { false }
    var isBillShowing: () -> Bool = { false }
    var isForeground: () -> Bool = { UIApplication.shared.applicationState == .active }
    /// Subscribes the mint and waits for the verified state the bill's give operation needs.
    var verifiedState: (ExchangedFiat) async -> VerifiedState? = { _ in nil }
    var present: (Session.BillDescription) -> Void = { _ in }

    /// Set by the open chat screen while it is on screen.
    var keyboard: (any ChatComposerKeyboard)?

    private var phase: Phase = .idle
    /// The message that earned the bill, recorded synchronously so the chat's receive haptic, which
    /// fires on the same transcript update, can skip it.
    private(set) var billedMessageID: MessageID?

    init(selfUserID: UserID) {
        self.selfUserID = selfUserID
        #if DEBUG
        registerDebugTrigger()
        #endif
    }

    /// Whether `messageID` is showing, or about to show, the bill, so the chat skips its own buzz.
    func isBilling(_ messageID: MessageID) -> Bool {
        billedMessageID == messageID
    }

    /// Considers a message that reached the client as a live stream event. Catch-up never comes here.
    func handleLive(_ messages: [ConversationMessage], in conversationID: ConversationID, countedThrough: MessageID?) {
        for message in messages {
            let context = ChatCashBill.Context(
                source: .live,
                selfUserID: selfUserID,
                messageConversationID: conversationID,
                openConversationID: openConversationID(),
                countedThrough: countedThrough,
                flagEnabled: isEnabled(),
                somethingOnTop: somethingOnTop() || !isForeground(),
                billBusy: phase != .idle || isBillShowing()
            )
            guard let amount = ChatCashBill.billAmount(for: message, in: context) else { continue }
            billedMessageID = message.id
            phase = .preparing(messageID: message.id)
            Task { await prepareAndShow(amount, messageID: message.id, in: conversationID) }
            // First one wins: the rest of the batch is dropped.
            return
        }
    }

    private func prepareAndShow(_ amount: ExchangedFiat, messageID: MessageID, in conversationID: ConversationID) async {
        let state = await verifiedState(amount)

        // Things may have moved during the wait: re-check what the decision checked.
        guard phase == .preparing(messageID: messageID) else { return }
        guard let state,
              openConversationID() == conversationID,
              !somethingOnTop(), isForeground(), !isBillShowing()
        else {
            logger.info("Chat cash bill dropped after preparing", metadata: [
                "hasVerifiedState": "\(state != nil)",
            ])
            abandon(messageID)
            return
        }

        let keyboardWasUp = keyboard?.isUp ?? false
        if keyboardWasUp { keyboard?.lower() }
        phase = .showing(restoreKeyboard: keyboardWasUp)
        present(.init(exchangedFiat: amount, received: true, verifiedState: state, announcesDeposit: false))
    }

    private func abandon(_ messageID: MessageID) {
        phase = .idle
        if billedMessageID == messageID { billedMessageID = nil }
    }

    /// Called after any bill closes. Gives the keyboard back only if this controller's bill took it
    /// and the app is still in front: a bill dismissed by backgrounding must not raise it.
    func billDidClose() {
        guard case .showing(let restoreKeyboard) = phase else { return }
        phase = .idle
        if restoreKeyboard, isForeground() {
            keyboard?.raise()
        }
    }

    #if DEBUG
    // MARK: - Debug trigger -

    /// Feeds a synthetic $1.00 payment to me through the live decision, for recording the bill and
    /// the keyboard without a second account. Never stored. Fire with
    /// `xcrun simctl spawn <udid> notifyutil -p flipcash.debug.chatCashBill`.
    private var debugToken: Int32 = 0

    private func registerDebugTrigger() {
        notify_register_dispatch("flipcash.debug.chatCashBill", &debugToken, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireDebugPayment() }
        }
    }

    private func fireDebugPayment() {
        guard let conversationID = openConversationID() else {
            logger.info("Debug chat cash bill: no chat open")
            return
        }
        let message = ConversationMessage(
            id: MessageID(value: UInt64(Date().timeIntervalSince1970)),
            senderID: UUID(),
            content: .cash(ExchangedFiat(nativeAmount: .usd(1), rate: .oneToOne)),
            cashAction: .sent,
            cashReceiverID: selfUserID,
            date: .now,
            unreadSeq: 0
        )
        handleLive([message], in: conversationID, countedThrough: nil)
    }
    #endif
}
