//
//  TabBarProfilePhoto.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// What the You tab draws in its icon slot, for a profile that has a picture.
///
/// Nil-vs-case rather than a bare optional photo: "no picture at all" and "a
/// picture that hasn't loaded" want different slots, and only the first of them
/// should fall back to the outline glyph.
enum ProfileTabSlot: Equatable {
    /// The picture's thumbnail hasn't been read back yet, carrying its BlurHash
    /// preview — nil for a picture stored before the hash was, which draws the
    /// ring empty rather than falling back to the glyph.
    case pending(UIImage?)
    case photo(UIImage)

    /// What `ProfileTabIcon` draws inside the ring.
    var preview: UIImage? {
        switch self {
        case .pending(let blurred): blurred
        case .photo(let picture):   picture
        }
    }
}

/// The You tab's icon once the profile carries a picture: the photo in a ring,
/// standing in the slot the outline glyph otherwise occupies (Figma node
/// 9713:664).
///
/// The ring is the selection: the active tab wears a 2pt solid white one, an
/// inactive tab a 1pt half-opacity one. That is a state the glyph tabs don't
/// have — they only ever dim — so it has to be drawn here rather than left to
/// whichever bar is hosting the icon.
///
/// A nil photo draws the ring empty. That is the state a cold launch starts in:
/// the profile says a picture exists well before its thumbnail is read back, and
/// the ring holds the slot so the glyph never shows to someone who has one.
struct ProfileTabIcon: View {

    let photo: UIImage?

    /// Whether the You tab is the active one, which picks the ring.
    let isSelected: Bool

    /// The slot every tab glyph is drawn into, so the photo sits on the same
    /// baseline as its neighbours.
    static let slotSize: CGFloat = 32

    private static let circleSize: CGFloat = 28
    private static let selectedRingWidth: CGFloat = 2
    private static let unselectedRingWidth: CGFloat = 1

    private var ringWidth: CGFloat {
        isSelected ? Self.selectedRingWidth : Self.unselectedRingWidth
    }

    private var ringColor: Color {
        // Half opacity on top of the half the whole icon is already drawn at,
        // so the inactive ring lands at the quarter alpha Figma specifies.
        isSelected ? .white : Color.white.opacity(0.5)
    }

    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.2)
            }
        }
        .frame(width: Self.circleSize, height: Self.circleSize)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(ringColor, lineWidth: ringWidth)
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

        // A failed fetch leaves the previous icon up rather than clearing it: the
        // tab keeps whatever it was already drawing.
        guard let image = await ProfilePictureLoader.thumbnail(for: picture, using: client, owner: owner),
              !Task.isCancelled
        else { return }

        photo = image
        itemImages = Self.render(image)
        loadedBlobID = blobID
    }

    /// The bar renditions of a slot that is still loading, so the iOS 26 bar
    /// shows the BlurHash where the pill shows it too.
    ///
    /// Memoized on the preview because this is read from a view body: the decode
    /// behind it is already cached, but the two `ImageRenderer` passes are not.
    /// One entry is enough — a launch only ever waits on one picture.
    static func pendingItemImages(preview: UIImage?) -> ItemImages? {
        if memoizedPreview === preview, let memoizedPending { return memoizedPending }

        let rendered = render(preview)
        memoizedPreview = preview
        memoizedPending = rendered
        return rendered
    }

    private static var memoizedPreview: UIImage?
    private static var memoizedPending: ItemImages?

    /// Draws the icon into the pair of images a `UITabBarItem` holds.
    ///
    /// The bar tints template glyphs per state, but a photo has to render as its
    /// own colours — so the unselected state is baked in here instead: the
    /// thinner half-opacity ring, and the half opacity the pill applies to every
    /// other icon.
    static func render(_ photo: UIImage?) -> ItemImages? {
        guard let selected = image(of: ProfileTabIcon(photo: photo, isSelected: true)),
              let normal = image(of: ProfileTabIcon(photo: photo, isSelected: false).opacity(0.5))
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
