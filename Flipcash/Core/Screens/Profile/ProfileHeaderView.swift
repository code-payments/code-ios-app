//
//  ProfileHeaderView.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A profile's top block: cover, avatar overlapping it, name, handle and bio.
///
/// A nil `displayName` leaves the name block out, for a profile that has not named itself yet.
struct ProfileHeaderView<BannerActions: View, UnderHandle: View>: View {

    let userID: UserID
    let displayName: String?
    let handle: String?
    let bio: String?
    let avatarData: Data?
    let avatarBlurhash: String?
    let coverPicture: ProfilePicture?
    let customization: TipCardCustomization?
    let statusChip: AnyView?
    @ViewBuilder let bannerActions: () -> BannerActions
    @ViewBuilder let underHandle: () -> UnderHandle

    private static var avatarSize: CGFloat { 88 }

    var body: some View {
        VStack(spacing: 0) {
            ProfileCoverBanner(
                userID: userID,
                coverPicture: coverPicture,
                customization: customization,
                actions: bannerActions
            )

            ContactAvatarView(
                id: userID.uuidString,
                displayName: displayName ?? "",
                imageData: avatarData,
                blurhash: avatarBlurhash,
                size: Self.avatarSize
            )
            .overlay { Circle().strokeBorder(Color.backgroundMain, lineWidth: 4) }
            .padding(.top, -Self.avatarSize / 2)

            if let displayName {
                VStack(spacing: 4) {
                    Text(displayName)
                        .font(.appDisplaySmall)
                        .foregroundStyle(Color.textMain)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("profile-name")

                    if let handle {
                        Text(handle)
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityIdentifier("profile-handle")
                    }

                    underHandle()
                }
                .padding(.top, 12)

                if let statusChip {
                    statusChip
                        .padding(.top, 8)
                }

                if let bio, !bio.isEmpty {
                    Text(bio)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textMain)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .accessibilityIdentifier("profile-bio")
                }
            }
        }
    }
}
