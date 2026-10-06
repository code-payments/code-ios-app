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
    /// A picked image not uploaded yet, drawn in place of the stored cover.
    var preview: UIImage? = nil
    /// The banner's height; a profile's own cover is ``height``.
    var bannerHeight: CGFloat = Self.height
    @ViewBuilder let controls: () -> Controls

    static var height: CGFloat { 214 }

    var body: some View {
        Color.clear
            .frame(height: bannerHeight)
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
        if let preview {
            fill(preview)
        } else if let coverPicture {
            let data = sessionContainer.profileAvatars.data(for: .cover(userID))
            if let data, let image = ContactAvatarCache.shared.image(forKey: "cover-\(coverPicture.blobID)", data: data) {
                fill(image)
            } else if let preview = BlurHashCache.shared.image(for: coverPicture.thumbnailBlurhash) {
                fill(preview)
            } else {
                Color.coverPlaceholder
            }
        } else {
            Color.coverPlaceholder
        }
    }

    private func fill(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
    }
}

extension ProfileCoverBanner where Controls == EmptyView {

    /// A cover with nothing laid over it.
    init(userID: UserID, coverPicture: ProfilePicture?, preview: UIImage? = nil, bannerHeight: CGFloat = Self.height) {
        self.init(userID: userID, coverPicture: coverPicture, preview: preview, bannerHeight: bannerHeight, controls: { EmptyView() })
    }
}
