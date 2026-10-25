//
//  GroupSendDetailsSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// What the details sheet shows for a cash message paid to group members: no amounts per person.
nonisolated struct GroupSendDetails: Identifiable, Hashable, Sendable {

    /// Someone the sheet names, with what it needs for their avatar.
    struct Person: Hashable, Sendable {
        /// Nil when the payment doesn't say who it was; such a row doesn't open a profile.
        let userID: UserID?
        let name: String
        let picture: ProfilePicture?
    }

    let id: String
    let mint: PublicKey
    let from: Person
    let recipients: [Person]

    /// The details for `message`, or nil unless it is a payment in a group that names its
    /// recipients: two or more in `cashPayments`, or one in `cashReceiverID`. Names come from
    /// `members`; anyone it doesn't hold reads as "Someone", and the viewer as "You".
    init?(message: ConversationMessage, members: [ConversationMember], selfUserID: UserID) {
        guard case .cash(let fiat) = message.content else { return nil }
        let receivers: [UserID?] = message.cashPayments.count >= 2
            ? message.cashPayments.map(\.receiverID)
            : message.cashReceiverID.map { [$0] } ?? []
        guard !receivers.isEmpty else { return nil }
        let byID = Dictionary(
            members.compactMap { member in member.userID.map { ($0, member) } },
            uniquingKeysWith: { first, _ in first }
        )
        func person(_ userID: UserID?) -> Person {
            guard let userID else { return Person(userID: nil, name: "Someone", picture: nil) }
            let member = byID[userID]
            let name = userID == selfUserID ? "You" : member.map(ConversationLoadCoordinator.attributionName(for:)) ?? "Someone"
            return Person(userID: userID, name: name, picture: member?.profilePicture)
        }
        self.id = message.stableID
        self.mint = fiat.mint
        self.from = person(message.senderID)
        self.recipients = receivers.map(person)
    }
}

/// The sheet a group payment's cash card opens: the token sent, who sent it, and who was paid,
/// each row opening that token's or person's page.
struct GroupSendDetailsSheet: View {

    @Environment(Session.self) private var session
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(\.dismiss) private var dismiss

    let details: GroupSendDetails
    let openToken: (PublicKey) -> Void
    let openProfile: (UserID) -> Void

    var body: some View {
        PartialSheet(background: .clear) {
            VStack(spacing: 20) {
                ViewThatFits(in: .vertical) {
                    rows
                    ScrollView { rows }
                        .frame(maxHeight: 480)
                }
                CodeButton(style: .filled, title: "Close") {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 20)
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            tokenRow
            personRow(label: "From", details.from)
            ForEach(Array(details.recipients.enumerated()), id: \.offset) { index, person in
                personRow(label: index == 0 ? "To" : nil, person)
            }
        }
    }

    private var tokenRow: some View {
        let balance = session.balance(for: details.mint)
        return row(label: "Sent", action: { open { openToken(details.mint) } }) {
            TokenIconWithName(
                url: balance?.imageURL,
                monogramID: details.mint.base58,
                name: balance?.name ?? "Cash",
                iconSize: 40,
                font: .appTextMedium.bold()
            )
        }
        .accessibilityIdentifier("group-send-details-token")
    }

    private func personRow(label: String?, _ person: GroupSendDetails.Person) -> some View {
        let action = person.userID.map { userID in { open { openProfile(userID) } } }
        return row(label: label, action: action) {
            HStack(spacing: 8) {
                ContactAvatarView(
                    id: person.userID?.uuidString ?? person.name,
                    displayName: person.name,
                    imageData: person.userID.flatMap { sessionContainer.profileAvatars.data(for: $0) },
                    blurhash: person.picture?.thumbnailBlurhash,
                    size: 40
                )
                Text(person.name)
                    .font(.appTextMedium.bold())
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
            }
            .task(id: person.userID) {
                guard let userID = person.userID else { return }
                await sessionContainer.profileAvatars.load(userID: userID, picture: person.picture)
            }
        }
    }

    /// A label column, then `content`, with a chevron when the row opens something.
    private func row(label: String?, action: (() -> Void)?, @ViewBuilder content: () -> some View) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Text(label ?? "")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 40, alignment: .leading)
                content()
                Spacer(minLength: 0)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    /// Dismisses first, so the page opens on the chat's stack rather than under the sheet.
    private func open(_ destination: @escaping () -> Void) {
        dismiss()
        destination()
    }
}
