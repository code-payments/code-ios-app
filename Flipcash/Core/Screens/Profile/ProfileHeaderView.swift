//
//  ProfileHeaderView.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A profile's top block: a full-bleed cover, the avatar overlapping it, an action row, then name,
/// handle and bio, all left-aligned on a 24pt inset.
///
/// The caller lets the view run under the status bar. A nil `displayName` leaves the name block out,
/// for a profile that has not named itself yet.
struct ProfileHeaderView<BannerControls: View, RowActions: View, UnderHandle: View>: View {

    let userID: UserID
    let displayName: String?
    let handle: String?
    let bio: String?
    let avatarData: Data?
    let avatarBlurhash: String?
    let coverPicture: ProfilePicture?
    let statusChip: AnyView?
    @ViewBuilder let bannerControls: () -> BannerControls
    @ViewBuilder let rowActions: () -> RowActions
    @ViewBuilder let underHandle: () -> UnderHandle

    static var inset: CGFloat { 24 }

    private static var avatarSize: CGFloat { 84 }
    /// How far the avatar rises over the banner.
    private static var avatarOverlap: CGFloat { 42 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileCoverBanner(
                userID: userID,
                coverPicture: coverPicture,
                controls: bannerControls
            )

            HStack(alignment: .top, spacing: 0) {
                ContactAvatarView(
                    id: userID.uuidString,
                    displayName: displayName ?? "",
                    imageData: avatarData,
                    blurhash: avatarBlurhash,
                    size: Self.avatarSize
                )
                .overlay { Circle().strokeBorder(Color.backgroundMain, lineWidth: 5) }
                .padding(.top, -Self.avatarOverlap)

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    rowActions()
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, Self.inset)

            if let displayName {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(displayName)
                            .font(.appDisplaySmall)
                            .foregroundStyle(Color.textMain)
                            .accessibilityIdentifier("profile-name")

                        if let statusChip {
                            statusChip
                                .fixedSize()
                        }
                    }

                    if let handle {
                        Text(handle)
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityIdentifier("profile-handle")
                    }

                    underHandle()

                    if let bio, !bio.isEmpty {
                        Text(bio)
                            .font(.appTextBody)
                            .foregroundStyle(Color.textMain)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                            .accessibilityIdentifier("profile-bio")
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, Self.inset)
            }
        }
    }
}

/// The share button in the header's action row: an icon on the app's glass circle, the same chrome
/// as the toolbar's gear and ⋯.
struct ProfileActionCircle: View {

    let image: Image
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            image
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(Color.textMain)
        }
        .liquidGlassButtonStyle(shape: .circle)
    }
}

/// The header's "Edit Profile" button, a glass capsule beside ``ProfileActionCircle``.
struct ProfileEditCapsule: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Edit Profile")
                .font(.appTextSmall)
                .foregroundStyle(Color.textMain)
        }
        .liquidGlassButtonStyle()
    }
}
