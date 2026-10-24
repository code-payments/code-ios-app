//
//  GroupSendDetailsSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// What the details sheet shows for a cash message paid to several group members: no amounts per person.
nonisolated struct GroupSendDetails: Identifiable, Hashable, Sendable {
    let id: String
    let total: String
    let sentAt: Date
    let from: String
    let recipients: [String]

    /// The details for `message`, or nil when it isn't a payment split between two or more members.
    /// Names come from `members`; anyone it doesn't hold reads as "Someone", and the viewer as "You".
    init?(message: ConversationMessage, members: [ConversationMember], selfUserID: UserID) {
        guard case .cash(let fiat) = message.content, message.cashPayments.count >= 2 else { return nil }
        let byID = Dictionary(members.map { ($0.userID, $0) }, uniquingKeysWith: { first, _ in first })
        func name(_ userID: UserID?) -> String {
            guard let userID else { return "Someone" }
            if userID == selfUserID { return "You" }
            return byID[userID].map(ConversationLoadCoordinator.attributionName(for:)) ?? "Someone"
        }
        self.id = message.stableID
        self.total = fiat.nativeAmount.formatted()
        self.sentAt = message.date
        self.from = name(message.senderID)
        self.recipients = message.cashPayments.map { name($0.receiverID) }
    }
}

/// The sheet a group send's cash card opens: when, from whom, and who was paid.
struct GroupSendDetailsSheet: View {

    let details: GroupSendDetails

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Amount", details.total)
                    row("Sent", details.sentAt.formatted(date: .abbreviated, time: .shortened))
                    row("From", details.from)
                }
                Section("To \(details.recipients.count) People") {
                    ForEach(Array(details.recipients.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.backgroundMain)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.textMain)
        }
        .font(.appTextMedium)
    }
}
