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
                    Text(displayName)
                        .font(.appDisplaySmall)
                        .foregroundStyle(Color.textMain)
                        .accessibilityIdentifier("profile-name")

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

/// The share button in the header's action row: an icon on a flat filled circle.
struct ProfileActionCircle: View {

    let image: Image
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            image
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .frame(width: ProfileActionButtonStyle.height, height: ProfileActionButtonStyle.height)
        }
        .buttonStyle(ProfileActionButtonStyle())
    }
}

/// The header's "Edit Profile" button, a flat filled capsule beside ``ProfileActionCircle``.
struct ProfileEditCapsule: View {

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Edit Profile")
                .font(.appTextSmall)
                .padding(.horizontal, 18)
        }
        .buttonStyle(ProfileActionButtonStyle())
    }
}

/// The header buttons' chrome: a capsule filled at 10% of the action colour, one step above the
/// row tone of the stats card beneath them.
private struct ProfileActionButtonStyle: ButtonStyle {

    static var height: CGFloat { 38 }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.textMain)
            .frame(height: Self.height)
            .background(Capsule().fill(Color.action.opacity(0.1)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
