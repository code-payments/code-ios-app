//
//  EditProfileScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The signed-in user's profile fields in one list: cover, photo, then a row per field showing
/// its current value. Pushed from the You tab's Edit Profile button.
struct EditProfileScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(SessionContainer.self) private var sessionContainer

    @State private var dialog: DialogItem?

    private static let rowInsets = EdgeInsets(top: 25, leading: 20, bottom: 25, trailing: 20)

    private var session: Session { sessionContainer.session }
    private var profile: Profile? { session.profile }

    /// Whether the handle still needs claiming: none yet, or one the server assigned.
    private var needsUsernameClaim: Bool {
        usernameNeedsClaim(
            username: profile?.username,
            isAutoAssigned: profile?.isUsernameAutoAssigned == true
        )
    }

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    fieldRows
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Edit Profile")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialog)
        .task(id: profile?.profilePicture?.thumbnailBlobID) {
            await sessionContainer.profileAvatars.load(userID: session.userID, picture: profile?.profilePicture)
        }
    }

    // MARK: - Header -

    /// The You tab's cover and avatar at the same sizes, each a button to its own editor.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                router.push(.changeCoverPicture)
            } label: {
                ProfileCoverBanner(userID: session.userID, coverPicture: profile?.coverPicture)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("edit-profile-cover")

            Button {
                router.push(.changeProfilePicture)
            } label: {
                ContactAvatarView(
                    id: session.userID.uuidString,
                    displayName: profile?.displayName ?? "",
                    imageData: sessionContainer.profileAvatars.data(for: session.userID),
                    blurhash: profile?.profilePicture?.thumbnailBlurhash,
                    size: ProfileHeaderView<EmptyView, EmptyView, EmptyView>.avatarSize
                )
                .overlay { Circle().strokeBorder(Color.backgroundMain, lineWidth: 5) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("edit-profile-photo")
            .padding(.top, -ProfileHeaderView<EmptyView, EmptyView, EmptyView>.avatarOverlap)
            .padding(.leading, ProfileHeaderView<EmptyView, EmptyView, EmptyView>.inset)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Rows -

    @ViewBuilder
    private var fieldRows: some View {
        FieldRow(title: "Display Name", value: nonEmpty(profile?.displayName), placeholder: "Add a name", insets: Self.rowInsets) {
            router.push(.changeDisplayName)
        }
        .accessibilityIdentifier("edit-profile-name")

        usernameRow

        FieldRow(title: "Bio", value: nonEmpty(profile?.bio), placeholder: "Add a bio", insets: Self.rowInsets) {
            router.push(.editBio)
        }
        .accessibilityIdentifier("edit-profile-bio")

        FieldRow(title: "Minimum to Chat", value: minimumToChat, placeholder: "Not set", insets: Self.rowInsets) {
            router.push(.setMinimumTip(isSetupStep: false))
        }
        .accessibilityIdentifier("edit-profile-minimum")
    }

    @ViewBuilder
    private var usernameRow: some View {
        if needsUsernameClaim {
            FieldRow(title: "Username", value: "Claim your username", placeholder: "", insets: Self.rowInsets, valueIsPrompt: true, action: beginUsernameClaim)
                .accessibilityIdentifier("edit-profile-username")
        } else if let username = profile?.username {
            // No balance gate on a held handle: the gate exists to stop squatting at claim time,
            // and a user who already holds one has cleared it.
            FieldRow(title: "Username", value: "@\(username.value)", placeholder: "", insets: Self.rowInsets) {
                router.push(.username(username))
            }
            .accessibilityIdentifier("edit-profile-username")
        }
    }

    private var minimumToChat: String? {
        profile?.minDmChatInitFee?.formatted()
    }

    private func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    // MARK: - Username claim -

    /// The same entry the You tab's progress card takes: the claim screen once the balance clears
    /// the server's minimum, the balance dialog otherwise.
    private func beginUsernameClaim() {
        switch usernameGate(session: session, minimum: session.userFlags?.usernameMinBalance) {
        case .proceed:
            router.push(.username(profile?.username))
        case .addMoney(let minimum, _, _):
            dialog = .usernameMinimumBalance(minimum: minimum) {
                router.presentAddMoney(.general, source: .usernameShortfall)
            }
        }
    }
}

/// A tappable row with the field's title and its current value, one line, trailing.
private struct FieldRow: View {

    let title: String
    let value: String?
    let placeholder: String
    let insets: EdgeInsets
    var valueIsPrompt = false
    let action: VoidAction

    var body: some View {
        Row(insets: insets, accessory: .chevron) {
            Text(title)
                .font(.appDisplayXS)
                .foregroundStyle(Color.textMain)
            // `Row` puts its own spacer before the chevron, so the value claims the width to sit against it.
            Text(value ?? placeholder)
                .font(.appTextMedium)
                .foregroundStyle(value == nil || valueIsPrompt ? Color.textSecondary : Color.textMain)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } action: {
            action()
        }
    }
}
