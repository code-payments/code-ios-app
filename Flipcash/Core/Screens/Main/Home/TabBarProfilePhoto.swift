//
//  TabBarProfilePhoto.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.tab-bar-photo")

/// The You tab's icon once the profile carries a picture: the photo in a white
/// ring, standing in the slot the outline glyph otherwise occupies (Figma node
/// 9641:17115).
struct ProfileTabIcon: View {

    let photo: UIImage

    /// The slot every tab glyph is drawn into, so the photo sits on the same
    /// baseline as its neighbours.
    static let slotSize: CGFloat = 32

    private static let circleSize: CGFloat = 28
    private static let ringWidth: CGFloat = 2

    var body: some View {
        Image(uiImage: photo)
            .resizable()
            .scaledToFill()
            .frame(width: Self.circleSize, height: Self.circleSize)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(Color.white, lineWidth: Self.ringWidth)
            }
            .frame(width: Self.slotSize, height: Self.slotSize)
    }
}

/// Loads the signed-in profile's picture for the tab bar and keeps the UIKit
/// renditions alongside it.
///
/// Both bars need the same photo in different forms: the legacy pill draws
/// SwiftUI, while the iOS 26 bar takes `UITabBarItem` images. Rendering happens
/// once here, when the photo lands, rather than on every pass of either bar.
@Observable
final class TabBarProfilePhoto {

    /// The tab-bar renditions of one photo, in the two states the bar asks for.
    struct ItemImages: Equatable {
        let normal: UIImage
        let selected: UIImage
    }

    /// The downloaded picture, for the pill's SwiftUI icon. Nil while it loads,
    /// and for a profile with no picture — the tab keeps its glyph either way.
    private(set) var photo: UIImage?

    private(set) var itemImages: ItemImages?

    /// The blob the icons were rendered from, so re-running the load for a
    /// picture already on screen leaves it there.
    private var loadedBlobID: BlobID?

    /// Downloads `picture`'s thumbnail and renders the bar's icons from it.
    ///
    /// A failure is not surfaced: the tab falls back to the outline glyph, which
    /// is what it showed before there was a picture at all.
    func load(_ picture: ProfilePicture?, using client: FlipClient, owner: KeyPair) async {
        guard let blobID = picture?.thumbnailBlobID else {
            // No picture to show, so the tab goes back to its glyph.
            photo = nil
            itemImages = nil
            loadedBlobID = nil
            return
        }

        // A replaced picture keeps the previous photo up for the length of the
        // download. Blanking it first would blink the tab back to its glyph, and
        // this runs again whenever the profile is refreshed.
        guard blobID != loadedBlobID else { return }

        do {
            // Download URLs expire, so one is minted per load and never stored.
            guard let url = try await client.blobDownloadURL(blobID: blobID, owner: owner) else {
                logger.info("Profile picture blob has no download URL", metadata: ["blobId": "\(blobID)"])
                return
            }

            let image = try await RemoteImageLoader.image(at: url, cacheKey: blobID.description)
            guard !Task.isCancelled else { return }

            photo = image
            itemImages = Self.render(image)
            loadedBlobID = blobID
        } catch {
            guard !Task.isCancelled else { return }
            logger.info("Failed to load the profile picture for the tab bar", metadata: ["error": "\(error)"])
        }
    }

    /// Draws the icon into the pair of images a `UITabBarItem` holds.
    ///
    /// The bar tints template glyphs per state, but a photo has to render as its
    /// own colours — so the unselected dimming is baked in here instead, at the
    /// half opacity the pill applies to every other icon.
    static func render(_ photo: UIImage) -> ItemImages? {
        guard let selected = image(of: ProfileTabIcon(photo: photo)),
              let normal = image(of: ProfileTabIcon(photo: photo).opacity(0.5))
        else { return nil }

        return ItemImages(normal: normal, selected: selected)
    }

    private static func image(of icon: some View) -> UIImage? {
        let renderer = ImageRenderer(content: icon)
        renderer.scale = UIScreen.main.scale
        // Original rather than template: a tinted photo is a silhouette.
        return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
    }
}
