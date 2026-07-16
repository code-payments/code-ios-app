//
//  ContactActionPill.swift
//  FlipcashUI
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore

/// The counterpart call to action shared by the chat profile card and the profile page:
/// "View in Contacts" for a synced contact, "Add Contact" for an unknown one.
public struct ContactActionPill: View {

    let counterpart: ChatProfileCard.Counterpart
    let action: () -> Void

    public init(counterpart: ChatProfileCard.Counterpart, action: @escaping () -> Void) {
        self.counterpart = counterpart
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ContactActionLabel(counterpart: counterpart)
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    Capsule().fill(Color.white.opacity(0.1))
                }
        }
        .buttonStyle(.plain)
    }
}

/// The pill's label: view the existing contact, or add the unknown one.
private struct ContactActionLabel: View {

    let counterpart: ChatProfileCard.Counterpart

    var body: some View {
        switch counterpart {
        case .contact:
            Text("View in Contacts")
        case .unknown:
            Label {
                Text("Add Contact")
            } icon: {
                Image.system(.personBadgePlus)
            }
        }
    }
}
