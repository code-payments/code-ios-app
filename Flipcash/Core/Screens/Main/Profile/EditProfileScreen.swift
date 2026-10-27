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
                .padding(.horizontal, ProfileHeaderMetrics.inset)
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
            ProfileCoverBanner(cover: .user(session.userID, picture: profile?.coverPicture), bannerHeight: Self.coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("edit-profile-cover")
        .overlay(alignment: .topTrailing) {
            Button(EditProfileCopy.coverChip(hasCover: profile?.coverPicture != nil)) {
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

                Text(EditProfileCopy.photoCaption(hasPhoto: profile?.profilePicture != nil))
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

            FieldCard(title: "Minimum To Chat", value: minimumToChat, placeholder: "Not set") {
                router.push(.setMinimumTip(isSetupStep: false))
            }
            .accessibilityIdentifier("edit-profile-minimum")

            FieldCard(title: "Favorite Community Chats", value: featuredGroupsSummary, placeholder: "Add chats") {
                router.push(.editFeaturedGroups)
            }
            .accessibilityIdentifier("edit-profile-featured-groups")
        }
    }

    private var usernameCard: some View {
        FieldCard(
            title: "Username",
            value: EditProfileCopy.usernameValue(profile?.username),
            placeholder: "Add a username",
            action: openUsername
        )
        .accessibilityIdentifier("edit-profile-username")
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

    // MARK: - Username -

    /// A handle the user chose is opened directly: the balance gate exists to stop squatting at
    /// claim time, and a user who holds one has cleared it. Otherwise the gate decides between the
    /// claim screen and the balance dialog.
    private func openUsername() {
        let gate = usernameGate(session: session, minimum: session.userFlags?.usernameMinBalance)
        switch usernameRowDestination(needsClaim: needsUsernameClaim, gate: gate) {
        case .username:
            router.push(.username(profile?.username))
        case .balanceRequired(let minimum):
            dialog = .usernameMinimumBalance(minimum: ratesController.displayCurrency.amount(minimum)) {
                router.presentAddMoney(.general, source: .usernameShortfall)
            }
        }
    }
}

/// The Edit Profile strings that depend on what the profile already holds.
enum EditProfileCopy {
    /// The cover chip's label: "Add cover photo" until there is a cover, then "Change cover".
    static func coverChip(hasCover: Bool) -> String {
        hasCover ? "Change cover" : "Add cover photo"
    }

    /// The caption under the avatar: "Add profile photo" until there is a photo, then "Change photo".
    static func photoCaption(hasPhoto: Bool) -> String {
        hasPhoto ? "Change photo" : "Add profile photo"
    }

    /// The Username row's value, or nil when there is no handle to show.
    static func usernameValue(_ username: Username?) -> String? {
        username?.handle
    }
}
