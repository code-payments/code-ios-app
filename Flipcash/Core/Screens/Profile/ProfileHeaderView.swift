//
//  ProfileHeaderView.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The profile header's layout constants, shared with the sections laid out beneath it.
enum ProfileHeaderMetrics {

    /// The horizontal inset everything below the banner sits on.
    static var inset: CGFloat { 24 }

    static var avatarSize: CGFloat { 84 }
    /// How far the avatar rises over the banner.
    static var avatarOverlap: CGFloat { 42 }
}

/// A profile's top block: a full-bleed cover, the caller's avatar overlapping it, an action row,
/// then title, subtitle and body text, all left-aligned on a 24pt inset.
///
/// The caller lets the view run under the status bar. A nil `title` leaves the text block out,
/// for a profile that has not named itself yet.
struct ProfileHeaderView<Avatar: View, BannerControls: View, CoverAccessory: View, RowActions: View, UnderSubtitle: View>: View {

    let cover: ProfileCover
    let title: String?
    let subtitle: String?
    let bodyText: String?
    /// Drawn at ``ProfileHeaderMetrics/avatarSize``; the header adds the ring and the overlap.
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let bannerControls: () -> BannerControls
    /// Sits on the cover's bottom edge beside the avatar. The cover is a fixed height, so content
    /// that arrives late, such as a status chip, never moves the rest of the header.
    @ViewBuilder let coverAccessory: () -> CoverAccessory
    @ViewBuilder let rowActions: () -> RowActions
    @ViewBuilder let underSubtitle: () -> UnderSubtitle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileCoverBanner(
                cover: cover,
                stretchesOnOverscroll: true,
                controls: bannerControls
            )
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    coverAccessory()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, ProfileHeaderMetrics.inset + ProfileHeaderMetrics.avatarSize + 12)
                .padding(.trailing, ProfileHeaderMetrics.inset)
                .padding(.bottom, 8)
            }

            HStack(alignment: .top, spacing: 0) {
                avatar()
                    .overlay { Circle().strokeBorder(Color.backgroundMain, lineWidth: 5) }
                    .padding(.top, -ProfileHeaderMetrics.avatarOverlap)

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    rowActions()
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, ProfileHeaderMetrics.inset)

            if let title {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.appDisplaySmall)
                        .foregroundStyle(Color.textMain)
                        .accessibilityIdentifier("profile-name")

                    if let subtitle {
                        Text(subtitle)
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityIdentifier("profile-handle")
                    }

                    underSubtitle()

                    if let bodyText, !bodyText.isEmpty {
                        Text(bodyText)
                            .font(.appTextMessage)
                            .foregroundStyle(Color.textMain)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 12)
                            .accessibilityIdentifier("profile-bio")
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, ProfileHeaderMetrics.inset)
            }
        }
    }
}

/// A person's avatar for the header's avatar slot: their picture, or their monogram, at the
/// header's size.
struct ProfileHeaderAvatar: View {

    let id: String
    let displayName: String
    let imageData: Data?
    let blurhash: String?

    var body: some View {
        ContactAvatarView(
            id: id,
            displayName: displayName,
            imageData: imageData,
            blurhash: blurhash,
            size: ProfileHeaderMetrics.avatarSize
        )
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

/// The header's edit button ("Edit Profile" unless titled otherwise), a flat filled capsule beside ``ProfileActionCircle``.
struct ProfileEditCapsule: View {

    var title: String = "Edit Profile"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
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
