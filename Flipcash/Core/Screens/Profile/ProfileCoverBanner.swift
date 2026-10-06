//
//  ProfileCoverBanner.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A profile's full-bleed cover: the picture once it has loaded, the blurhash while it does, and a
/// flat gray when there is no picture.
///
/// Sized from the top of the screen, so the caller lets it run under the status bar.
struct ProfileCoverBanner<Controls: View>: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let userID: UserID
    let coverPicture: ProfilePicture?
    @ViewBuilder let controls: () -> Controls

    static var height: CGFloat { 214 }

    var body: some View {
        Color.clear
            .frame(height: Self.height)
            .frame(maxWidth: .infinity)
            .overlay { cover }
            .clipped()
            .overlay(alignment: .top) {
                controls()
            }
            .task(id: coverPicture?.blobID) {
                await sessionContainer.profileAvatars.load(.cover(userID), picture: coverPicture)
            }
            // `.contain` keeps the banner's controls as their own elements; a bare identifier
            // here would overwrite theirs.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile-cover")
    }

    @ViewBuilder
    private var cover: some View {
        if let coverPicture {
            let data = sessionContainer.profileAvatars.data(for: .cover(userID))
            if let data, let image = ContactAvatarCache.shared.image(forKey: "cover-\(coverPicture.blobID)", data: data) {
                shaded(image)
            } else if let preview = BlurHashCache.shared.image(for: coverPicture.thumbnailBlurhash) {
                shaded(preview)
            } else {
                Color.coverPlaceholder
            }
        } else {
            Color.coverPlaceholder
        }
    }

    private func shaded(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .overlay { Color.black.opacity(0.16) }
    }
}
