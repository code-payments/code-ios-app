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

/// How much of the address book the Send picker can show. Derived from
/// `CNAuthorizationStatus` once the picker is reachable — never `.notDetermined`,
/// which is gated to the priming screen.
nonisolated enum RecipientContactAccess: Equatable {
    case full       // .authorized — full directory
    case limited    // .limited (iOS 18+) — shared subset + "Add More Contacts" footer
    case denied     // .denied / .restricted — conversations only + CTA card

    /// `nil` when the status isn't picker-reachable — `.notDetermined` routes to
    /// the priming screen instead.
    init?(_ status: CNAuthorizationStatus) {
        switch status {
        case .authorized:           self = .full
        case .limited:              self = .limited
        case .denied, .restricted:  self = .denied
        case .notDetermined:        return nil
        @unknown default:           return nil
        }
    }
}

/// Send section's primary view. Renders `contactSyncController.resolvedContacts`.
struct RecipientPickerScreen: View {

    /// How much of the address book is available — drives the empty states and
    /// the list footer (limited → "Add More Contacts", denied → CTA card).
    let contactAccess: RecipientContactAccess

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
        // Denied always renders the list so the CTA card shows; full/limited fall
        // back to an empty state only when there's nothing to list.
        let showList = contactAccess == .denied || !(contacts.isEmpty && conversations.isEmpty)
        return Group {
            if showList {
                RecipientPickerList(
                    conversations: conversations,
                    filtered: filtered,
                    searchText: searchText,
                    contactAccess: contactAccess,
                    onConversationTap: openConversation,
                    onFlipcashTap: selectRecipient,
                    onInviteTap: presentInvite,
                )
            } else {
                switch contactAccess {
                case .limited: LimitedAccessEmptyState()
                case .full:    RecipientPickerEmptyState()
                case .denied:  EmptyView()  // unreachable — denied always shows the list
                }
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
                        "outcome": "\(result)",
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
        inviteTarget = contact
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

/// One row of the picker: a synced contact, a DM conversation, or both joined
/// by the contact's `dmChatID`. `partition(...)` sorts these into the "Recents"
/// section (rows backed by a conversation, newest activity first) and the
/// "On Flipcash" section (chat-less contacts, in the directory's order).
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

    /// Splits picker rows into the two sections the list renders. `contacts` is
    /// the already-filtered on-Flipcash set; `conversationNames` carries each
    /// chat's resolved display name and is consulted only while searching, to
    /// keep contact-less chats whose name matches the query.
    nonisolated static func partition(
        contacts: [ResolvedContact],
        conversations: [Conversation],
        searchText: String,
        conversationNames: [ConversationID: String]
    ) -> (recents: [RecipientListItem], onFlipcash: [RecipientListItem]) {
        var unmatched: [ConversationID: Conversation] = [:]
        for conversation in conversations {
            unmatched[conversation.id] = conversation
        }

        var recents: [RecipientListItem] = []
        var onFlipcash: [RecipientListItem] = []
        for contact in contacts {
            if let chatID = contact.dmChatID.map(ConversationID.init(data:)),
               let conversation = unmatched.removeValue(forKey: chatID) {
                recents.append(.matched(contact, conversation))
            } else {
                onFlipcash.append(.contact(contact))
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for conversation in conversations where unmatched[conversation.id] != nil {
            let matchesSearch = query.isEmpty || (conversationNames[conversation.id]?.lowercased().contains(query) ?? false)
            if matchesSearch {
                recents.append(.conversation(conversation))
            }
        }

        recents.sort { ($0.conversation?.lastActivity ?? .distantPast) > ($1.conversation?.lastActivity ?? .distantPast) }
        return (recents, onFlipcash)
    }
}

// MARK: - List -

private struct RecipientPickerList: View {

    let conversations: [Conversation]
    let filtered: ResolvedContacts
    let searchText: String
    let contactAccess: RecipientContactAccess
    let onConversationTap: (Conversation) -> Void
    let onFlipcashTap: (ResolvedContact) -> Void
    let onInviteTap: (ResolvedContact) -> Void

    @Environment(ConversationController.self) private var conversationController

    /// Chat display names keyed by conversation, resolved through the controller
    /// so the search matches what each row shows. Built only while searching.
    private var conversationNames: [ConversationID: String] {
        guard !searchText.isEmpty else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: conversations.map { ($0.id, conversationController.displayName(for: $0)) }
        )
    }

    private var partitioned: (recents: [RecipientListItem], onFlipcash: [RecipientListItem]) {
        RecipientListItem.partition(
            contacts: filtered.onFlipcash,
            conversations: conversations,
            searchText: searchText,
            conversationNames: conversationNames
        )
    }

    var body: some View {
        let sections = partitioned
        List {
            if !sections.recents.isEmpty {
                Section {
                    ForEach(sections.recents) { item in
                        RecipientListItemRow(item: item, onTap: { tap(item) })
                    }
                } header: {
                    RecipientSectionHeader(title: "Recents")
                }
                .listSectionSeparator(.hidden, edges: .top)
            }
            if !sections.onFlipcash.isEmpty {
                Section {
                    ForEach(sections.onFlipcash) { item in
                        RecipientListItemRow(item: item, onTap: { tap(item) })
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
            switch contactAccess {
            case .denied:
                SendMoneyPromoCard()
                    .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            case .limited:
                if !filtered.isEmpty {
                    AddMoreContactsFooter()
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            case .full:
                EmptyView()
            }
        }
        .listStyle(.grouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // New messages re-sort and re-style rows — animate those moves. Keyed
        // to the feed so search-driven filtering stays instant.
        .animation(.snappy, value: conversations)
        .overlay {
            // "No Results" only when neither a contact nor a chat matched — a
            // chat can match on its name while no contact does. Skipped under
            // denied access so the CTA card stays visible.
            if !searchText.isEmpty && filtered.isEmpty && sections.recents.isEmpty && contactAccess != .denied {
                RecipientSearchEmptyState(searchText: searchText)
            }
        }
    }

    private func tap(_ item: RecipientListItem) {
        switch item {
        case .contact(let contact), .matched(let contact, _):
            onFlipcashTap(contact)
        case .conversation(let conversation):
            onConversationTap(conversation)
        }
    }
}

// MARK: - Rows -

/// The chrome every picker row shares: a full-row button with avatar,
/// title/subtitle, and a trailing accessory.
private struct RecipientRowScaffold<Trailing: View>: View {

    let avatarID: String
    let title: String
    let subtitle: String?
    let imageData: Data?
    let accessibilityLabel: String
    let onTap: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        Button(action: onTap) {
            RecipientRowBody(
                avatarID: avatarID,
                title: title,
                subtitle: subtitle,
                imageData: imageData
            ) {
                trailing
            }
        }
        .recipientRowChrome(accessibilityLabel: accessibilityLabel)
    }
}

/// The visual content of a picker row: avatar, title/subtitle, and a trailing
/// accessory. Shared by the tappable `RecipientRowScaffold` and the `ShareLink`
/// invite-fallback row.
private struct RecipientRowBody<Trailing: View>: View {

    let avatarID: String
    let title: String
    let subtitle: String?
    let imageData: Data?
    @ViewBuilder let trailing: Trailing

    var body: some View {
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
                if let subtitle {
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .contentShape(Rectangle())
    }
}

private extension View {
    /// Row chrome shared by every picker row: list insets, clear background,
    /// separator tint, and single-element button accessibility. Applied to the
    /// row's `Button` or `ShareLink`.
    func recipientRowChrome(accessibilityLabel: String) -> some View {
        self
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(.rowSeparator)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits(.isButton)
    }
}

/// A merged "On Flipcash" row. Rows with a conversation show the last-message
/// preview; chatless contacts and chats with no messages show no subtitle. An
/// unread chat marks the row with a leading dot.
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

    private var subtitle: String? {
        switch item {
        case .contact:
            return nil
        case .conversation(let conversation), .matched(_, let conversation):
            guard let message = conversation.lastMessage else { return nil }
            switch message.content {
            case .text(let text):
                return text
            case .cash(let amount):
                let verb = message.isFromSelf(conversationController.selfUserID) ? "You sent" : "You received"
                return "\(verb) \(amount.nativeAmount.formatted())"
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

    private var accessibilityLabel: String {
        let base = subtitle.map { "\(title), \($0)" } ?? title
        return hasUnread ? "\(base), unread messages" : base
    }

    var body: some View {
        RecipientRowScaffold(
            avatarID: avatarID,
            title: title,
            subtitle: subtitle,
            imageData: item.contact?.imageData,
            accessibilityLabel: accessibilityLabel,
            onTap: onTap
        ) {
            Image(systemName: "chevron.right")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
        }
        .overlay(alignment: .leading) {
            if hasUnread {
                // Offset into the row's leading inset so the dot sits in the
                // margin left of the avatar.
                Circle()
                    .fill(Color.unreadIndicator)
                    .frame(width: 10, height: 10)
                    .offset(x: -15)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A "Not on Flipcash Yet" row. With iMessage available the whole row opens the
/// invite composer; otherwise it shares the download link through the system
/// share sheet via `ShareLink`, so SwiftUI owns the presentation.
private struct RecipientRow: View {

    let contact: ResolvedContact
    let onInvite: () -> Void

    private var accessibilityLabel: String {
        "\(contact.displayName), \(contact.nationalPhone)"
    }

    var body: some View {
        if MessageComposerSheet.isAvailable {
            RecipientRowScaffold(
                avatarID: contact.contactId,
                title: contact.displayName,
                subtitle: contact.nationalPhone,
                imageData: contact.imageData,
                accessibilityLabel: accessibilityLabel,
                onTap: onInvite
            ) {
                InvitePill()
            }
            .accessibilityActions {
                Button("Invite", action: onInvite)
            }
        } else {
            ShareLink(item: URL.downloadApp) {
                RecipientRowBody(
                    avatarID: contact.contactId,
                    title: contact.displayName,
                    subtitle: contact.nationalPhone,
                    imageData: contact.imageData
                ) {
                    InvitePill()
                }
            }
            .recipientRowChrome(accessibilityLabel: accessibilityLabel)
        }
    }
}

/// The trailing "Invite" pill on a "Not on Flipcash Yet" row.
private struct InvitePill: View {
    var body: some View {
        Text("Invite")
            .pill(.standard)
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
