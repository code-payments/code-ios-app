//
//  RecipientPickerScreen.swift
//  Flipcash
//

import Contacts
import MessageUI
import SwiftUI
import FlipcashCore
import FlipcashUI

nonisolated private let logger = Logger(label: "flipcash.recipient-picker")

/// Send section's primary view. Renders `contactSyncController.resolvedContacts`.
struct RecipientPickerScreen: View {

    /// `true` when contacts are shared under iOS 18 limited access. Drives the
    /// limited-access empty state shown when nothing has been shared yet.
    let isLimitedAccess: Bool

    /// Injected from `SendRootScreen`, which owns the `.searchable`. The search
    /// field has to be present from the moment the Send sheet mounts — a
    /// `.searchable` added later (when the recipient list appears) gets placed by
    /// iOS 26 as a floating bottom field instead of the nav-bar drawer.
    let searchText: String

    @Environment(ContactSyncController.self) private var contactSyncController
    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    @State private var filtered: ResolvedContacts = .empty
    @State private var inviteTarget: ResolvedContact?

    var body: some View {
        let contacts = contactSyncController.resolvedContacts
        let conversations = conversationController.conversations
        return Group {
            if contacts.isEmpty && conversations.isEmpty {
                if isLimitedAccess {
                    LimitedAccessEmptyState()
                } else {
                    RecipientPickerEmptyState()
                }
            } else {
                RecipientPickerList(
                    conversations: conversations,
                    filtered: filtered,
                    searchText: searchText,
                    isLimitedAccess: isLimitedAccess,
                    onConversationTap: openConversation,
                    onFlipcashTap: selectRecipient,
                    onInviteTap: presentInvite,
                )
            }
        }
        .onAppear { refilter() }
        .onChange(of: searchText) { refilter() }
        .onChange(of: contacts) { withAnimation(.snappy) { refilter() } }
        .sheet(item: $inviteTarget) { contact in
            MessageComposerSheet(
                recipient: contact.phoneE164,
                onFinish: { result in
                    logger.info("Invite composer finished", metadata: [
                        "outcome": "\(outcomeName(result))",
                    ])
                    inviteTarget = nil
                },
            )
        }
    }

    // MARK: - Tap -

    private func selectRecipient(_ contact: ResolvedContact) {
        Analytics.track(event: Analytics.SendEvent.tapRecipient)
        router.push(.dmConversation(.contact(contact)))
    }

    private func openConversation(_ conversation: Conversation) {
        router.push(.dmConversation(.existing(conversation.id)))
    }

    private func presentInvite(for contact: ResolvedContact) {
        if MessageComposerSheet.isAvailable {
            inviteTarget = contact
        } else {
            // iMessage isn't configured on this device (iPad without SIM, etc.).
            // Fall back to the system share sheet with the download URL only.
            logger.info("Presenting share fallback (iMessage unavailable)")
            ShareSheet.present(url: URL.downloadApp)
        }
    }

    private func outcomeName(_ result: MessageComposeResult) -> String {
        switch result {
        case .sent:       return "sent"
        case .cancelled:  return "cancelled"
        case .failed:     return "failed"
        @unknown default: return "unknown"
        }
    }

    private func refilter() {
        filtered = contactSyncController.resolvedContacts.filtered(by: searchText)
    }
}

// MARK: - Empty states -

private struct RecipientPickerEmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Text("No Contacts Found")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
        } description: {
            Text("None of the people in your address book have a phone number we can match.")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

/// Shown under iOS 18 limited access when no contacts have been shared. Routes
/// to Settings to pick contacts — adding them in-app is unavailable on iOS 26
/// (FB14821786).
private struct LimitedAccessEmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Text("No Contacts Shared")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
        } description: {
            Text("Choose which contacts to share with Flipcash, then you can send them cash.")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
        } actions: {
            BubbleButton(text: "Choose in Settings") {
                URL.openSettings()
            }
        }
    }
}

/// Footer under the populated recipient list in iOS limited access. Routes to
/// Settings to share more contacts — adding them in-app is unavailable on
/// iOS 26 (FB14821786).
private struct LimitedAccessSettingsFooter: View {
    var body: some View {
        Button {
            URL.openSettings()
        } label: {
            Text("Choose more contacts in Settings")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// Shown over the list when a search matches no contacts.
private struct RecipientSearchEmptyState: View {

    let searchText: String

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No Results for “\(searchText)”")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
            } icon: {
                Image(systemName: "magnifyingglass")
            }
        } description: {
            Text("Check the spelling or try a new search.")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

// MARK: - List items -

/// One row of the merged "On Flipcash" section: a synced contact, a DM
/// conversation, or both joined by the contact's `dmChatID`. Rows with a
/// conversation sort by activity (newest first) ahead of chat-less contacts,
/// which keep the directory's order.
nonisolated enum RecipientListItem: Identifiable, Equatable {

    case contact(ResolvedContact)
    case conversation(Conversation)
    case matched(ResolvedContact, Conversation)

    var id: String {
        switch self {
        case .contact(let contact), .matched(let contact, _):
            contact.id
        case .conversation(let conversation):
            conversation.id.description
        }
    }

    var contact: ResolvedContact? {
        switch self {
        case .contact(let contact), .matched(let contact, _):
            contact
        case .conversation:
            nil
        }
    }

    var conversation: Conversation? {
        switch self {
        case .contact:
            nil
        case .conversation(let conversation), .matched(_, let conversation):
            conversation
        }
    }

    static func items(contacts: [ResolvedContact], conversations: [Conversation]) -> [RecipientListItem] {
        var unmatched: [ConversationID: Conversation] = [:]
        for conversation in conversations {
            unmatched[conversation.id] = conversation
        }

        var active: [RecipientListItem] = []
        var chatless: [RecipientListItem] = []
        for contact in contacts {
            if let chatID = contact.dmChatID.map(ConversationID.init(data:)),
               let conversation = unmatched.removeValue(forKey: chatID) {
                active.append(.matched(contact, conversation))
            } else {
                chatless.append(.contact(contact))
            }
        }
        for conversation in conversations where unmatched[conversation.id] != nil {
            active.append(.conversation(conversation))
        }

        active.sort { ($0.conversation?.lastActivity ?? .distantPast) > ($1.conversation?.lastActivity ?? .distantPast) }
        return active + chatless
    }
}

// MARK: - List -

private struct RecipientPickerList: View {

    let conversations: [Conversation]
    let filtered: ResolvedContacts
    let searchText: String
    let isLimitedAccess: Bool
    let onConversationTap: (Conversation) -> Void
    let onFlipcashTap: (ResolvedContact) -> Void
    let onInviteTap: (ResolvedContact) -> Void

    /// Searching filters by contact, so conversations whose counterpart isn't
    /// a synced contact only appear with an empty query — matched rows keep
    /// their conversation join either way.
    private var items: [RecipientListItem] {
        var items = RecipientListItem.items(contacts: filtered.onFlipcash, conversations: conversations)
        if !searchText.isEmpty {
            items.removeAll { item in
                if case .conversation = item { true } else { false }
            }
        }
        return items
    }

    var body: some View {
        List {
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        RecipientListItemRow(
                            item: item,
                            onTap: {
                                switch item {
                                case .contact(let contact), .matched(let contact, _):
                                    onFlipcashTap(contact)
                                case .conversation(let conversation):
                                    onConversationTap(conversation)
                                }
                            }
                        )
                    }
                } header: {
                    RecipientSectionHeader(title: "On Flipcash")
                }
                .listSectionSeparator(.hidden, edges: .top)
            }
            if !filtered.invite.isEmpty {
                Section {
                    ForEach(filtered.invite) { contact in
                        RecipientRow(
                            contact: contact,
                            onInvite: { onInviteTap(contact) }
                        )
                    }
                } header: {
                    RecipientSectionHeader(title: "Not on Flipcash Yet")
                }
                .listSectionSeparator(.hidden, edges: .top)
            }
            if isLimitedAccess && !filtered.isEmpty {
                LimitedAccessSettingsFooter()
            }
        }
        .listStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // New messages re-sort and re-style rows — animate those moves. Keyed
        // to the feed so search-driven filtering stays instant.
        .animation(.snappy, value: conversations)
        .overlay {
            if !searchText.isEmpty && filtered.isEmpty {
                RecipientSearchEmptyState(searchText: searchText)
            }
        }
    }
}

// MARK: - Rows -

/// The chrome every picker row shares: a full-row button with avatar,
/// title/subtitle, and a trailing accessory.
private struct RecipientRowScaffold<Trailing: View>: View {

    let avatarID: String
    let title: String
    let subtitle: String
    let imageData: Data?
    let accessibilityLabel: String
    let onTap: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ContactAvatarView(
                    id: avatarID,
                    displayName: title,
                    imageData: imageData,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                trailing
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(.rowSeparator)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }
}

/// A merged "On Flipcash" row. Contact rows show the phone number; rows with
/// a conversation show the last-message preview and swap the chevron for the
/// unread dot while the chat has unread messages.
private struct RecipientListItemRow: View {

    let item: RecipientListItem
    let onTap: () -> Void

    @Environment(ConversationController.self) private var conversationController

    private var title: String {
        switch item {
        case .contact(let contact), .matched(let contact, _):
            contact.displayName
        case .conversation(let conversation):
            conversationController.displayName(for: conversation)
        }
    }

    private var subtitle: String {
        switch item {
        case .contact(let contact):
            contact.nationalPhone
        case .conversation(let conversation), .matched(_, let conversation):
            switch conversation.lastMessage?.content {
            case .text(let text): text
            case .cash(let amount): "Cash · \(amount.nativeAmount.formatted())"
            case nil: "No messages yet"
            }
        }
    }

    private var hasUnread: Bool {
        item.conversation?.hasUnread(for: conversationController.selfUserID) ?? false
    }

    private var avatarID: String {
        switch item {
        case .contact(let contact), .matched(let contact, _):
            contact.contactId
        case .conversation(let conversation):
            conversation.id.description
        }
    }

    var body: some View {
        RecipientRowScaffold(
            avatarID: avatarID,
            title: title,
            subtitle: subtitle,
            imageData: item.contact?.imageData,
            accessibilityLabel: hasUnread ? "\(title), \(subtitle), unread messages" : "\(title), \(subtitle)",
            onTap: onTap
        ) {
            if hasUnread {
                Circle()
                    .fill(Color.unreadIndicator)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}

/// A "Not on Flipcash Yet" row: the whole row and its trailing button both
/// start an invite.
private struct RecipientRow: View {

    let contact: ResolvedContact
    let onInvite: () -> Void

    var body: some View {
        RecipientRowScaffold(
            avatarID: contact.contactId,
            title: contact.displayName,
            subtitle: contact.nationalPhone,
            imageData: contact.imageData,
            accessibilityLabel: "\(contact.displayName), \(contact.nationalPhone)",
            onTap: onInvite
        ) {
            Text("Invite")
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: Metrics.buttonRadius)
                        .fill(Color.backgroundRow)
                }
        }
        .accessibilityActions {
            Button("Invite", action: onInvite)
        }
    }
}

// MARK: - Section header -

/// Section header. The list uses `.listStyle(.grouped)` so headers don't float;
/// plain-style sticky headers misplace under the iOS 26 `.searchable` bar (no
/// first-party way to pin them flush). Mirrors `CurrencySelectionScreen`.
/// `Color.backgroundMain` matches the sheet backdrop.
private struct RecipientSectionHeader: View {

    let title: String

    var body: some View {
        Text(title)
            .textCase(.none)
            .font(.appTextSmall)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundMain)
            .listRowInsets(EdgeInsets())
    }
}
