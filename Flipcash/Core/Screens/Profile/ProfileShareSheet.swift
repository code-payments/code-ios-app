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
    case copyLink
}

/// The bottom sheet behind a profile's Share button: share the link, show the profile card, or copy the link.
///
/// A row dismisses the sheet and reports its choice through `onChoose`; the presenter acts on it from
/// the sheet's `onDismiss`, so a share sheet or cover never presents over a sheet that is leaving.
/// `offersCard` false drops the card row, for a profile that has no card to show.
struct ProfileShareSheet: View {

    let subtitle: String?
    let offersCard: Bool
    let onChoose: (ProfileShareChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(r: 102, g: 102, b: 106))
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Share User Profile")
                    .font(.default(size: 21, weight: .semibold))
                    .foregroundStyle(Color.textMain)
                if let subtitle {
                    Text(subtitle)
                        .font(.default(size: 13, weight: .regular))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            row(icon: Image.asset(.shareOS), title: "Share Profile", identifier: "profile-share-row", choice: .share)
            if offersCard {
                separator
                row(icon: Image(systemName: "person.crop.rectangle"), title: "Show Profile Card", identifier: "profile-card-row", choice: .showCard)
            }
            separator
            row(icon: Image.asset(.chainLink), title: "Copy Link", identifier: "profile-copy-link-row", choice: .copyLink)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.backgroundSecondary)
        .presentationCornerRadius(28)
    }

    /// Handle, title block and rows, plus a small bottom margin. The sheet floats clear of the home
    /// indicator on its own, so no extra room is added for it.
    private var detentHeight: CGFloat {
        let rows: CGFloat = offersCard ? 3 : 2
        return 12 + 4 + 20 + 52 + 12 + rows * 64 + 8
    }

    private var separator: some View {
        Color(r: 58, g: 58, b: 60)
            .frame(height: 1)
            .padding(.leading, 54)
    }

    private func row(icon: Image, title: String, identifier: String, choice: ProfileShareChoice) -> some View {
        Button {
            onChoose(choice)
            dismiss()
        } label: {
            HStack(spacing: 6) {
                icon
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(.default(size: 16, weight: .medium))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.textSecondary)
            }
            .foregroundStyle(Color.textMain)
            .padding(.leading, 24)
            .padding(.trailing, 24)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
