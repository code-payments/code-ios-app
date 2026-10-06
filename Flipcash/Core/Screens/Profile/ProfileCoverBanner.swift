//
//  ProfileCoverBanner.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What a cover banner draws: the picture, and the subject its bytes load and authorize under.
struct ProfileCover {

    let subject: ProfileAvatarStore.AvatarSubject
    let picture: ProfilePicture?

    private init(subject: ProfileAvatarStore.AvatarSubject, picture: ProfilePicture?) {
        self.subject = subject
        self.picture = picture
    }

    /// A user's cover.
    static func user(_ userID: UserID, picture: ProfilePicture?) -> ProfileCover {
        ProfileCover(subject: .cover(userID), picture: picture)
    }

    /// A group chat's cover.
    static func group(_ conversationID: ConversationID, picture: ProfilePicture?) -> ProfileCover {
        ProfileCover(subject: .groupCover(conversationID), picture: picture)
    }
}

/// A profile's full-bleed cover: the picture once it has loaded, the blurhash while it does, and a
/// flat gray when there is no picture.
///
/// Sized from the top of the screen, so the caller lets it run under the status bar.
struct ProfileCoverBanner<Controls: View>: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let cover: ProfileCover
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
            .overlay { image }
            .clipped()
            .overlay(alignment: .top) {
                controls()
            }
            .task(id: cover.picture?.blobID) {
                await sessionContainer.profileAvatars.load(cover.subject, picture: cover.picture)
            }
            // `.contain` keeps the banner's controls as their own elements; a bare identifier
            // here would overwrite theirs.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile-cover")
    }

    @ViewBuilder
    private var image: some View {
        if let preview {
            fill(preview)
        } else if let coverPicture = cover.picture {
            let data = sessionContainer.profileAvatars.data(for: cover.subject)
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
    init(cover: ProfileCover, preview: UIImage? = nil, bannerHeight: CGFloat = Self.height) {
        self.init(cover: cover, preview: preview, bannerHeight: bannerHeight, controls: { EmptyView() })
    }
}
