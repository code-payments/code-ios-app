//
//  ProfileShareSheet.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// What a row of ``ProfileShareSheet`` asks for.
enum ProfileShareChoice {
    case share
    case showCard
}

/// The bottom sheet behind the You tab's Share button: share the profile, or show the profile card.
/// Drawn as the "Add Money With" sheet is. Other people's profiles and groups share through
/// ``ShareToChatsSheet`` directly.
///
/// A row dismisses the sheet and reports its choice through `onChoose`; the presenter acts on it from
/// the sheet's `onDismiss`, so a following sheet or cover never presents over a sheet that is leaving.
struct ProfileShareSheet: View {

    let onChoose: (ProfileShareChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PartialSheet {
            VStack(spacing: 12) {
                HStack {
                    Text("Share User Profile")
                        .font(.appBarButton)
                        .foregroundStyle(Color.textMain)
                    Spacer()
                }
                .padding(.vertical, 20)

                row(icon: Image.asset(.shareOS), title: "Share Profile", identifier: "profile-share-row", choice: .share)
                row(icon: Image(systemName: "person.crop.rectangle"), title: "Show Profile Card", identifier: "profile-card-row", choice: .showCard)

                Button("Dismiss") { dismiss() }
                    .buttonStyle(.subtle)
            }
            .padding(.horizontal)
            .padding(.top)
        }
    }

    private func row(icon: Image, title: String, identifier: String, choice: ProfileShareChoice) -> some View {
        // The Add Money rows' fill, which reads on this sheet's lighter background.
        ChatActionRow(icon: icon, title: title, background: Color.white.opacity(0.1), accessibilityIdentifier: identifier) {
            onChoose(choice)
            dismiss()
        }
    }
}
