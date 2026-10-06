//
//  ProfileCoverBanner.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A profile's 3:1 cover: the picture once it has loaded, the blurhash while it does, and the
/// profile-card colour when there is no picture.
struct ProfileCoverBanner<Actions: View>: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let userID: UserID
    let coverPicture: ProfilePicture?
    let customization: TipCardCustomization?
    @ViewBuilder let actions: () -> Actions

    private static var aspectRatio: CGFloat { 3 }

    var body: some View {
        Color.clear
            .aspectRatio(Self.aspectRatio, contentMode: .fit)
            .overlay { cover }
            .overlay(alignment: .topTrailing) {
                actions()
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .task(id: coverPicture?.blobID) {
                await sessionContainer.profileAvatars.load(.cover(userID), picture: coverPicture)
            }
            // `.contain` keeps the Share and Settings buttons as their own elements; a bare
            // identifier here would overwrite theirs.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile-cover")
    }

    @ViewBuilder
    private var cover: some View {
        if let coverPicture {
            let data = sessionContainer.profileAvatars.data(for: .cover(userID))
            if let data, let image = ContactAvatarCache.shared.image(forKey: "cover-\(coverPicture.blobID)", data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let preview = BlurHashCache.shared.image(for: coverPicture.thumbnailBlurhash) {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
            } else {
                ProfileCoverFill.color(for: customization)
            }
        } else {
            ProfileCoverFill.color(for: customization)
        }
    }
}
