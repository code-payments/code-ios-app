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

    var title: String = "Share User Profile"
    let subtitle: String?
    /// The first row, which reports ``ProfileShareChoice/share``.
    var shareRow: (title: String, icon: Image) = ("Share Profile", Image.asset(.shareOS))
    let offersCard: Bool
    let onChoose: (ProfileShareChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PartialSheet(background: .backgroundMain) {
            VStack(spacing: 20) {
                header

                if let subtitle {
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        // Same floor as ``MuteChatSheet``'s caption: `PartialSheet` can propose less
                        // height than the text needs while it corrects to its measured size.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }

                VStack(spacing: 12) {
                    row(icon: shareRow.icon, title: shareRow.title, identifier: "profile-share-row", choice: .share)
                    if offersCard {
                        row(icon: Image(systemName: "person.crop.rectangle"), title: "Show Profile Card", identifier: "profile-card-row", choice: .showCard)
                    }
                    row(icon: Image.asset(.chainLink), title: "Copy Link", identifier: "profile-copy-link-row", choice: .copyLink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, bottomPadding)
        }
    }

    /// Centred title with a close button, the same title bar as ``MuteChatSheet``.
    private var header: some View {
        ZStack {
            Text(title)
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)

            HStack {
                Spacer()
                CloseButton(style: .glass) { dismiss() }
            }
        }
    }

    /// 16 under the last row, less what the sheet already holds back for the home indicator.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 16 - reserved)
    }

    private func row(icon: Image, title: String, identifier: String, choice: ProfileShareChoice) -> some View {
        ChatActionRow(icon: icon, title: title, accessibilityIdentifier: identifier) {
            onChoose(choice)
            dismiss()
        }
    }
}
