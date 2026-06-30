//
//  ConversationScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import Combine
import Contacts
import ContactsUI
import FlipcashCore
import FlipcashUI

// Traces when the on-screen conversation is set or cleared — the signal both the receive haptic and
// foreground-banner suppression gate on — so a missed buzz or an unsuppressed banner is traceable.
private let logger = Logger(label: "flipcash.conversation")

/// How a conversation is reached: an existing DM chat from the Chats section,
/// or a synced contact whose chat may not exist yet — the first cash payment
/// creates it server-side.
nonisolated enum ConversationContext: Hashable {
    case existing(ConversationID)
    case contact(ResolvedContact)
}

/// A DM conversation: an iMessage-style transcript over a Send Cash / Send
/// Message action bar. Reads live messages from `ConversationController`,
/// which owns the single event stream. For a contact without a chat the
/// transcript stays empty and only Send Cash shows; once the first payment
/// creates the chat, the chat ID resolves live from the synced directory and
/// Send Message appears.
struct ConversationScreen: View {

    let context: ConversationContext

    @Environment(ConversationController.self) private var conversationController
    @Environment(ContactSyncController.self) private var contactSyncController
    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(PushController.self) private var pushController

    @State private var didInitialRead = false
    @State private var barModel = ConversationBarModel()
    @State private var navBarWidth: CGFloat = 0
    @State private var presentedCard: ContactCard?

    /// Horizontal space the back button (leading) reserves on each side of the
    /// centered title item, so the avatar + name can left-align inside a
    /// centered, full-width principal stack.
    private static let titleSideInset: CGFloat = 72

    /// The synced contact for the counterpart, resolved live from the directory
    /// so a `dmChatID` stored after the first payment flows in. Falls back to
    /// the pushed snapshot when the directory hasn't resolved yet.
    private var contact: ResolvedContact? {
        let directory = contactSyncController.resolvedContacts.onFlipcash
        switch context {
        case .contact(let contact):
            return directory.first { $0.id == contact.id } ?? contact
        case .existing(let conversationID):
            return directory.first { $0.dmChatID == conversationID.data }
        }
    }

    private var conversationID: ConversationID? {
        switch context {
        case .existing(let conversationID):
            return conversationID
        case .contact:
            return contact?.dmChatID.map(ConversationID.init(data:))
        }
    }

    /// Who Send Cash pays: the synced address-book contact when there is one,
    /// otherwise a target built from the counterpart's shared phone number so a
    /// chat with a non-contact can still receive cash. `nil` only when neither a
    /// contact nor a counterpart phone number is available.
    private var sendTarget: ResolvedContact? {
        if let contact {
            return contact
        }
        guard let conversationID else { return nil }
        return ResolvedContact.sendTarget(
            in: conversationController.conversation(withID: conversationID),
            dmChatID: conversationID.data,
            selfUserID: conversationController.selfUserID
        )
    }

    /// Whether the DM chat actually exists server-side. Matched contacts carry
    /// a pre-assigned `dmChatID` before any payment (the first intent needs it),
    /// so the ID alone doesn't mean the chat was created — require it to be in
    /// the feed or to have messages.
    private var chatExists: Bool {
        guard let conversationID else { return false }
        switch context {
        case .existing:
            return true
        case .contact:
            return conversationController.conversation(withID: conversationID) != nil
                || conversationController.hasMessages(for: conversationID)
        }
    }

    /// Tapping the title opens the counterpart's contact card: their address-book
    /// card when they're a contact, otherwise the native "Add to Contacts" sheet
    /// seeded with their number. Inert only when neither a contact nor a phone
    /// number is known.
    private var titleTapAction: (() -> Void)? {
        guard contact != nil || addableContactPhone != nil else { return nil }
        return { openContactCard() }
    }

    /// The counterpart's phone number when they're NOT yet an address-book
    /// contact — the seed for the native "Add to Contacts" sheet.
    private var addableContactPhone: String? {
        guard contact == nil else { return nil }
        return sendTarget?.phoneE164
    }

    private var title: String {
        if let conversationID {
            return conversationController.displayName(forConversationID: conversationID)
        }
        return contact?.displayName ?? ConversationController.fallbackCounterpartName
    }

    private var messages: [ConversationMessage] {
        guard let conversationID else { return [] }
        return conversationController.messages(for: conversationID)
    }

    /// The newest server-confirmed message — what the receive buzz and mark-read track. Optimistic
    /// pending sends render after the confirmed run, so they must not drive these signals (an unresolved
    /// send would otherwise sit at the transcript's tail and mask incoming messages).
    private var latestConfirmedMessage: ConversationMessage? {
        guard let conversationID else { return nil }
        return conversationController.lastConfirmedMessage(for: conversationID)
    }

    /// The transcript's messages mapped to the UIKit chat's display items (messages + date
    /// separators). Cash branding mirrors the SwiftUI bubble: USDF reads as "Cash"; a launchpad
    /// currency uses its cached name + icon.
    private var mappedItems: [ChatItem] {
        var items = ChatItem.from(
            messages,
            selfUserID: conversationController.selfUserID,
            counterpartRead: counterpartRead.map { (pointer: $0.pointer, date: $0.date) },
            suppressReceiptFor: conversationController.settlingSendID,
            cashBranding: { fiat in
                guard let balance = session.balance(for: fiat.mint) else { return ("Cash", nil) }
                return (balance.name, balance.imageURL)
            }
        )
        if let conversationID, conversationController.isCounterpartTyping(in: conversationID) {
            items.append(.typingIndicator)
        }
        return items
    }

    /// The counterpart's read watermark + time, read live from the observable
    /// controller so the receipt updates the moment they read.
    private var counterpartRead: ReadReceiptState? {
        guard let conversationID else { return nil }
        return conversationController.conversation(withID: conversationID)?
            .counterpartReadReceipt(excluding: conversationController.selfUserID)
    }

    var body: some View {
        // The UIKit transcript hosts the bar internally and owns all keyboard handling, so there's
        // no SwiftUI `.safeAreaInset` bar here.
        ChatScreenRepresentable(
            items: mappedItems,
            onReachTop: loadOlderMessages,
            onRetry: retry,
            onCashCardTap: openCurrencyInfo,
            showsSendCash: sendTarget != nil,
            showsSendMessage: chatExists,
            conversationID: conversationID,
            onSendCash: sendCash,
            conversationController: conversationController,
            barModel: barModel
        )
        .ignoresSafeArea(.keyboard)
        // Extend the transcript under the navigation bar so content scrolls beneath it — that's
        // what lets the iOS 26 toolbar scroll-edge effect materialize. The collection view keeps a
        // top content inset (it adjusts for the safe area) so messages stay readable below the bar.
        .ignoresSafeArea(.container, edges: .top)
        .background(Color.backgroundMain)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ConversationTitleItem(
                    title: title,
                    contact: contact,
                    conversationID: conversationID,
                    width: max(navBarWidth - Self.titleSideInset * 2, 0),
                    onTap: titleTapAction
                )
            }
        }
        .sheet(item: $presentedCard) { card in
            ContactCardView(card: card)
                .ignoresSafeArea()
        }
        .background {
            // Measure the bar width so the centered title item can be sized to
            // (almost) fill it — the system toolbar won't honor maxWidth on a
            // principal item, so an explicit width is the only way to let the
            // avatar + name left-align inside a centered, full-width stack.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { navBarWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in navBarWidth = width }
            }
        }
        // While composing, a downward swipe should lower the keyboard — not
        // tear down the whole Send sheet.
        .interactiveDismissDisabled(barModel.isComposing)
        // Keyed on existence, not just the ID: a matched contact's chat ID is
        // pre-assigned, and fetching messages for a chat the server hasn't
        // created yet error-reports. Fires when the chat materializes.
        .task(id: chatExists ? conversationID : nil) {
            guard chatExists, let conversationID else { return }
            await conversationController.loadMessages(for: conversationID)
            await conversationController.markRead(conversationID: conversationID)
            // Reading the thread clears its own delivered pushes; other chats keep theirs.
            await pushController.clearDeliveredNotifications(for: conversationID)
            didInitialRead = true
        }
        .onChange(of: latestConfirmedMessage?.stableID) {
            // Fires on a live arrival or our own send. Marking read on our own send is intentional: it
            // advances the self-read watermark past the message we just sent, so the conversation
            // doesn't show as unread in the feed. didInitialRead skips the opening load (the .task
            // already marked read), and markRead short-circuits when the watermark already covers it.
            guard didInitialRead, let conversationID else { return }
            conversationController.scheduleMarkRead(conversationID: conversationID)
        }
        // Buzz on a live message from the other side while this conversation is on screen. `old != nil`
        // and `didInitialRead` skip the opening history load; the sender and visibility checks skip the
        // user's own sends and arrivals in a chat they've navigated away from.
        .sensoryFeedback(.impact(weight: .light), trigger: latestConfirmedMessage?.stableID) { old, _ in
            guard old != nil, didInitialRead,
                  let last = latestConfirmedMessage,
                  !last.isFromSelf(conversationController.selfUserID),
                  conversationController.visibleConversationID == conversationID
            else { return false }
            return true
        }
        .onAppear {
            setVisibleConversation(conversationID, source: "onAppear")
        }
        // Send Cash stacks the amount entry as a cover, so the chat stays
        // mounted and `onAppear` won't re-fire when it's dismissed. Poll for the
        // chat the first payment just created the moment that cover tears down.
        .onChange(of: router.presentedSheet) { old, _ in
            if case .sendAmount? = old { refreshChatBinding() }
        }
        // A matched contact's chat is created mid-screen on the first payment,
        // flipping the ID from nil to the new conversation; track it live.
        .onChange(of: conversationID) { _, id in
            setVisibleConversation(id, source: "onChange")
        }
        .onDisappear {
            // Guarded so a forward push that already set another ID isn't cleared.
            let matched = conversationController.visibleConversationID == conversationID
            logger.info("Clearing visible conversation on disappear", metadata: [
                "conversationID": conversationID.map { "\($0)" } ?? "nil",
                "matched": "\(matched)",
            ])
            if matched {
                conversationController.visibleConversationID = nil
            }
        }
        // Donate the open chat for Siri prediction, Handoff, and Spotlight.
        // Only an existing chat carries an id worth resuming; a contact without
        // a chat yet has nothing to hand off to.
        .userActivity(AppUserActivity.openChat, isActive: chatExists && conversationID != nil) { activity in
            guard let conversationID else { return }
            activity.title = title
            activity.userInfo = [AppUserActivity.chatIDKey: conversationID.base64URLEncoded]
            activity.requiredUserInfoKeys = [AppUserActivity.chatIDKey]
            activity.persistentIdentifier = conversationID.base64URLEncoded
            activity.isEligibleForSearch = true
            activity.isEligibleForHandoff = true
            activity.isEligibleForPrediction = true
        }
    }

    /// Marks this conversation as the one on screen — the gate for foreground-banner suppression and
    /// the receive haptic — and traces the change so a first-open visibility gap is diagnosable.
    private func setVisibleConversation(_ id: ConversationID?, source: String) {
        logger.info("Set visible conversation", metadata: [
            "source": "\(source)",
            "conversationID": id.map { "\($0)" } ?? "nil",
        ])
        conversationController.visibleConversationID = id
    }

    /// Opens the native iOS contact card for the counterpart. An address-book
    /// contact shows their card (fetched with the descriptor
    /// `CNContactViewController` requires; nothing is shown if it can't be read,
    /// e.g. deleted since sync). A non-contact with a known number opens the
    /// "Add to Contacts" sheet seeded with that number.
    private func openContactCard() {
        if let contactId = contact?.contactId {
            let keys = [CNContactViewController.descriptorForRequiredKeys()]
            guard let fetched = try? CNContactStore().unifiedContact(
                withIdentifier: contactId,
                keysToFetch: keys
            ) else { return }
            presentedCard = .existing(fetched)
        } else if let phone = addableContactPhone {
            let unknown = CNMutableContact()
            unknown.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))
            ]
            presentedCard = .unknown(unknown)
        }
    }

    private func sendCash() {
        guard let sendTarget else { return }
        guard session.hasGiveableBalance(for: ratesController.rateForBalanceCurrency()) else {
            session.dialogItem = .noGiveableBalance {
                router.navigate(to: .deposit)
            }
            return
        }
        router.presentNested(.sendAmount(sendTarget))
    }

    /// Re-send a failed message tapped in the transcript. The id is the row's stable id, which for a
    /// failed message is its client message id.
    private func retry(messageID: String) {
        guard let conversationID, let clientMessageID = UUID(uuidString: messageID) else { return }
        Task { await conversationController.retry(clientMessageID: clientMessageID, in: conversationID) }
    }

    /// Push the tapped cash card's token currency info onto the current chat stack (so back returns
    /// here). The id is the row's stable id; resolve it to the cash message's mint.
    private func openCurrencyInfo(messageID: String) {
        guard let message = messages.first(where: { $0.stableID == messageID }) else { return }
        switch message.content {
        case .cash(let fiat):
            router.push(.currencyInfo(fiat.mint))
        case .text:
            break
        }
    }

    /// Fetches the next older page when the UIKit transcript nears the top. Guarded so the
    /// continuously-fired signal never stacks requests or pages past the first message.
    private func loadOlderMessages() {
        guard let conversationID,
              conversationController.hasMoreOlderMessages(for: conversationID),
              !conversationController.isLoadingOlderMessages(for: conversationID) else { return }
        Task { await conversationController.loadOlderMessages(for: conversationID) }
    }

    /// After returning from the amount screen for a contact's first payment,
    /// the server has just created the chat (best-effort, so poll briefly).
    /// The event stream usually delivers the cash message on its own; this
    /// covers the gaps — a missing pre-assigned dmChatID, the stale feed (the
    /// picker's Chats section), and a missed stream event.
    private func refreshChatBinding() {
        guard case .contact = context, !chatExists else { return }
        Task {
            for attempt in 0..<3 {
                if attempt > 0 {
                    try? await Task.delay(seconds: 2)
                }
                if conversationID == nil {
                    await Task.detached { [contactSyncController] in
                        await contactSyncController.refreshMatchedSet()
                    }.value
                }
                guard let conversationID else { continue }
                await conversationController.loadFeed()
                // Done only once the FEED has the chat — messages arriving over
                // the stream flip `chatExists` early, but the picker's Recents
                // section reads the feed.
                guard conversationController.conversation(withID: conversationID) != nil else { continue }
                await conversationController.loadMessages(for: conversationID)
                break
            }
        }
    }
}

// MARK: - Title -

/// Avatar + name, left-aligned inside the centered principal slot (sized to
/// the measured bar width; the system toolbar won't honor maxWidth on a
/// principal item). When `onTap` is non-nil the whole item becomes a button
/// that opens the counterpart's contact card.
private struct ConversationTitleItem: View {

    let title: String
    let contact: ResolvedContact?
    let conversationID: ConversationID?
    let width: CGFloat
    let onTap: (() -> Void)?

    var body: some View {
        let label = ConversationTitleLabel(
            title: title,
            contact: contact,
            conversationID: conversationID,
            width: width
        )
        if let onTap {
            Button(action: onTap) { label }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityHint(contact != nil ? "Opens contact card" : "Adds to Contacts")
        } else {
            label
        }
    }
}

private struct ConversationTitleLabel: View {

    let title: String
    let contact: ResolvedContact?
    let conversationID: ConversationID?
    let width: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(
                id: contact?.contactId ?? conversationID?.description ?? title,
                displayName: title,
                imageData: contact?.imageData,
                size: 44
            )
            .accessibilityHidden(true)
            Text(title)
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
    }
}
