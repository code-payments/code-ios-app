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
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController

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
        guard session.hasGiveableBalance(for: ratesController.rateForBalanceCurrency()) else {
            session.dialogItem = .noGiveableBalance {
                router.navigate(to: .deposit)
            }
            return
        }
        router.push(.sendAmount(contact: contact))
    }

    private func openConversation(_ conversation: Conversation) {
        router.push(.dmConversation(conversationID: conversation.id))
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

// MARK: - List -

private struct RecipientPickerList: View {

    let conversations: [Conversation]
    let filtered: ResolvedContacts
    let searchText: String
    let isLimitedAccess: Bool
    let onConversationTap: (Conversation) -> Void
    let onFlipcashTap: (ResolvedContact) -> Void
    let onInviteTap: (ResolvedContact) -> Void

    var body: some View {
        List {
            if searchText.isEmpty && !conversations.isEmpty {
                Section {
                    ForEach(conversations) { conversation in
                        ConversationRow(conversation: conversation, onTap: { onConversationTap(conversation) })
                    }
                } header: {
                    RecipientSectionHeader(title: "Chats")
                }
                .listSectionSeparator(.hidden, edges: .top)
            }
            if !filtered.onFlipcash.isEmpty {
                Section {
                    ForEach(filtered.onFlipcash) { contact in
                        RecipientRow(
                            contact: contact,
                            trailing: .chevron,
                            onTap: { onFlipcashTap(contact) }
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
                            trailing: .invite { onInviteTap(contact) },
                            onTap: { onInviteTap(contact) }
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
        .overlay {
            if !searchText.isEmpty && filtered.isEmpty {
                RecipientSearchEmptyState(searchText: searchText)
            }
        }
    }
}

// MARK: - Row -

private enum RecipientRowTrailing {
    case chevron
    case invite(() -> Void)
}

private struct RecipientRow: View {

    let contact: ResolvedContact
    let trailing: RecipientRowTrailing
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ContactAvatarView(
                    id: contact.contactId,
                    displayName: contact.displayName,
                    imageData: contact.imageData,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                    Text(contact.nationalPhone)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                RecipientRowTrailingAccessory(trailing: trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(.rowSeparator)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(contact.displayName), \(contact.nationalPhone)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            if case .invite(let action) = trailing {
                Button("Invite", action: action)
            }
        }
    }
}

private struct RecipientRowTrailingAccessory: View {

    let trailing: RecipientRowTrailing

    var body: some View {
        switch trailing {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
        case .invite(let action):
            Button(action: action) {
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
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Conversation row -

/// A DM conversation row. The server doesn't yet hydrate member profiles, so the title
/// falls back to "Flipcash User" when the counterpart's display name is empty.
private struct ConversationRow: View {

    let conversation: Conversation
    let onTap: () -> Void

    @Environment(ConversationController.self) private var conversationController

    private var title: String {
        conversationController.displayName(for: conversation)
    }

    private var preview: String {
        switch conversation.lastMessage?.content {
        case .text(let text): text
        case .cash(let amount): "Cash · \(amount.nativeAmount.formatted())"
        case nil: "No messages yet"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ContactAvatarView(
                    id: conversation.id.description,
                    displayName: title,
                    imageData: nil,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                    Text(preview)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(.rowSeparator)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
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
