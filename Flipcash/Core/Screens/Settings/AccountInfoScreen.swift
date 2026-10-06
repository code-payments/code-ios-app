//
//  AccountInfoScreen.swift
//  Flipcash
//

import SwiftUI
import UIKit
import FlipcashUI
import FlipcashCore

/// The account's phone, email, user ID and owner public key. Tapping a row
/// copies its value.
struct AccountInfoScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ToastController.self) private var toasts

    var body: some View {
        let session = sessionContainer.session
        let rows = AccountInfoDetails.rows(
            profile: session.profile,
            userID: session.userID,
            authority: session.owner.authorityPublicKey
        )

        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.self) { row in
                        Button {
                            copy(row)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                    .font(.appTextHeading)
                                    .foregroundStyle(Color.textSecondary)
                                Text(row.display)
                                    .font(.appTextMedium)
                                    .foregroundStyle(Color.textMain)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(row.accessibilityID)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .navigationTitle("Account Info")
        .toolbarTitleDisplayMode(.inline)
    }

    private func copy(_ row: AccountInfoDetails.Row) {
        UIPasteboard.general.string = row.copyValue
        toasts.show(.init("Copied", systemImage: "checkmark.circle.fill", duration: .seconds(2)))
    }
}
