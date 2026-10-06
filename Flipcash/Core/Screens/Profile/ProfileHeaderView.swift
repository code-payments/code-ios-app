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

                HStack(spacing: 14) {
                    rowActions()
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, Self.inset)

            if let displayName {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(displayName)
                            .font(.default(size: 28, weight: .bold))
                            .tracking(-0.6)
                            .lineSpacing(1)
                            .frame(minHeight: 35)
                            .foregroundStyle(Color.textMain)
                            .accessibilityIdentifier("profile-name")

                        if let statusChip {
                            statusChip
                                .fixedSize()
                        }
                    }

                    if let handle {
                        Text(handle)
                            .font(.default(size: 14, weight: .regular))
                            .frame(minHeight: 22)
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityIdentifier("profile-handle")
                    }

                    underHandle()

                    if let bio, !bio.isEmpty {
                        Text(bio)
                            .font(.default(size: 15, weight: .regular))
                            .lineSpacing(4)
                            .foregroundStyle(Color.textMain)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 14)
                            .accessibilityIdentifier("profile-bio")
                    }
                }
                .padding(.top, 7)
                .padding(.horizontal, Self.inset)
            }
        }
    }
}

/// A 38pt disc in the header's action row, filled at the row-surface tint.
struct ProfileActionCircle: View {

    let image: Image

    var body: some View {
        image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 22)
            .foregroundStyle(Color.textMain)
            .frame(width: 38, height: 38)
            .background(Color.rowSeparator, in: Circle())
            .contentShape(Circle())
    }
}

/// The header's "Edit Profile" capsule.
struct ProfileEditCapsule: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Edit Profile")
                .font(.default(size: 12, weight: .semibold))
                .foregroundStyle(Color.textMain)
                .padding(.horizontal, 18)
                .frame(height: 38)
                .background(Color.rowSeparator, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
