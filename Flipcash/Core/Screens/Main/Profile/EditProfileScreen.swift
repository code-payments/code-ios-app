//
//  EditProfileScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The signed-in user's profile fields as cards under an inset cover and photo, each opening its own
/// editor. Pushed from the You tab's Edit Profile button.
struct EditProfileScreen: View {

    @Environment(AppRouter.self) private var router
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(RatesController.self) private var ratesController

    @State private var dialog: DialogItem?

    private static let coverHeight: CGFloat = 126
    private static let avatarSize: CGFloat = 68
    private static let cardSpacing: CGFloat = 12

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
                    cover
                    photo
                    fieldCards
                        .padding(.top, 20)
                }
                .padding(.horizontal, ProfileHeaderView<EmptyView, EmptyView, EmptyView>.inset)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Edit Profile")
        .toolbarTitleDisplayMode(.inline)
        .dialog(item: $dialog)
        .task(id: profile?.profilePicture?.thumbnailBlobID) {
            await sessionContainer.profileAvatars.load(userID: session.userID, picture: profile?.profilePicture)
        }
    }

    // MARK: - Cover & photo -

    private var cover: some View {
        Button {
            router.push(.changeCoverPicture)
        } label: {
            ProfileCoverBanner(userID: session.userID, coverPicture: profile?.coverPicture, bannerHeight: Self.coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("edit-profile-cover")
        .overlay(alignment: .topTrailing) {
            Button("Change cover") {
                router.push(.changeCoverPicture)
            }
            .buttonStyle(.plain)
            .modifier(CoverChip())
            .padding(Self.cardSpacing)
            .accessibilityIdentifier("edit-profile-change-cover")
        }
    }

    /// The avatar overlapping the cover's bottom edge, with a camera badge and a caption beside it.
    private var photo: some View {
        Button {
            router.push(.changeProfilePicture)
        } label: {
            HStack(alignment: .bottom, spacing: Self.cardSpacing) {
                ContactAvatarView(
                    id: session.userID.uuidString,
                    displayName: profile?.displayName ?? "",
                    imageData: sessionContainer.profileAvatars.data(for: session.userID),
                    blurhash: profile?.profilePicture?.thumbnailBlurhash,
                    size: Self.avatarSize
                )
                .overlay { Circle().strokeBorder(Color.backgroundMain, lineWidth: 5) }
                .overlay(alignment: .bottomTrailing) { cameraBadge }

                Text("Change photo")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("edit-profile-photo")
        .padding(.top, -Self.avatarSize / 2)
        .padding(.leading, 16)
    }

    private var cameraBadge: some View {
        Image.asset(.camera)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .frame(width: 28, height: 28)
            // Opaque so the avatar doesn't show through; the same grey as the header's buttons.
            .background(Circle().fill(Color.action.opacity(0.1)))
            .background(Circle().fill(Color.backgroundMain))
            .offset(x: 6, y: 2)
    }

    // MARK: - Fields -

    private var fieldCards: some View {
        VStack(spacing: Self.cardSpacing) {
            FieldCard(title: "Name", value: nonEmpty(profile?.displayName), placeholder: "Add a name") {
                router.push(.changeDisplayName)
            }
            .accessibilityIdentifier("edit-profile-name")

            usernameCard

            FieldCard(title: "Bio", value: nonEmpty(profile?.bio), placeholder: "Add a bio", lineLimit: 3) {
                router.push(.editBio)
            }
            .accessibilityIdentifier("edit-profile-bio")

            FieldCard(title: "Minimum to Chat", value: minimumToChat, placeholder: "Not set") {
                router.push(.setMinimumTip(isSetupStep: false))
            }
            .accessibilityIdentifier("edit-profile-minimum")

            FieldCard(title: "Favorite Public Groups", value: featuredGroupsSummary, placeholder: "Add groups") {
                router.push(.editFeaturedGroups)
            }
            .accessibilityIdentifier("edit-profile-featured-groups")
        }
    }

    @ViewBuilder
    private var usernameCard: some View {
        if needsUsernameClaim {
            FieldCard(title: "Username", value: "Claim your username", placeholder: "", valueIsPrompt: true, action: beginUsernameClaim)
                .accessibilityIdentifier("edit-profile-username")
        } else if let username = profile?.username {
            // No balance gate on a held handle: the gate exists to stop squatting at claim time,
            // and a user who already holds one has cleared it.
            FieldCard(title: "Username", value: "@\(username.value)", placeholder: "") {
                router.push(.username(username))
            }
            .accessibilityIdentifier("edit-profile-username")
        }
    }

    /// How many groups the profile features, or nil for none.
    private var featuredGroupsSummary: String? {
        let count = sessionContainer.featuredGroups.groups.count
        guard count > 0 else { return nil }
        return count == 1 ? "1 group" : "\(count) groups"
    }

    /// What others pay to start a chat, matching the You tab's stats card.
    private var minimumToChat: String? {
        StartChattingFee.amount(for: profile, session: session, ratesController: ratesController)?.formatted()
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

/// A tappable card with the field's title over its current value, styled like the profile's stats card.
private struct FieldCard: View {

    let title: String
    let value: String?
    let placeholder: String
    var valueIsPrompt = false
    var lineLimit = 1
    let action: VoidAction

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                    Text(value ?? placeholder)
                        .font(.appTextMedium)
                        .foregroundStyle(value == nil || valueIsPrompt ? Color.textSecondary : Color.textMain)
                        .lineLimit(lineLimit)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The "Change cover" button over the cover photo: an interactive Liquid Glass capsule on iOS 26, and on iOS 18 an
/// opaque chip, since the standard chip's row fill is translucent and vanishes on a photo.
private struct CoverChip: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(Color.backgroundMain.opacity(0.6)).interactive(), in: .capsule)
        } else {
            content.chip(.tinted(.textMain, on: .backgroundMain))
        }
    }
}
