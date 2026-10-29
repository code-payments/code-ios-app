//
//  PublicGroupLook.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The numbers of the public group profile's cover-colored page.
enum PublicGroupLook {

    /// How strongly the cover's own color is boosted before it becomes the page.
    static let saturation: Double = 1.2

    /// The OKLab lightness the page is pulled toward.
    static let lightnessDark: Double = 0.1

    /// How far toward ``lightnessDark`` the cover's color moves.
    static let lightnessPull: Double = 0.6

    /// The length of the melt from the cover into the page.
    static let fadeHeight: CGFloat = 214

    /// The cover's height from the top of the screen, under the status and navigation bars.
    static let coverHeight: CGFloat = 320

    /// How far below the navigation bar's bottom edge the identity (the avatar onward) starts; the
    /// cover stays put, so a larger value moves the avatar down into the melt.
    static let contentOffset: CGFloat = 4

    /// Whether the identity's avatar is drawn inside a ring of the page's color.
    static let avatarStroke: Bool = true

    /// The width of that ring.
    static let avatarStrokeWidth: CGFloat = 3

    // MARK: Boxes and spacing

    /// The corner radius of every box: the requirement tiles and the pulse card.
    static let cardRadius: CGFloat = 24

    /// The padding inside every box.
    static let cardPadding: CGFloat = 16

    /// The space above and below the hairline in a box, between its summary and the row under it.
    static let dividerGap: CGFloat = 12

    /// The gap from the pulse card's facepile to its headline.
    static let facepileToHeadline: CGFloat = 12

    /// The gap from the pulse card's headline to its meta line.
    static let headlineToMeta: CGFloat = 2

    /// The gap between boxes, stacked and side by side.
    static let cardGap: CGFloat = 12

    /// The gap above the closing action under the boxes, such as Leave Chat.
    static let leaveGap: CGFloat = 12

    /// Whether Leave Chat's label is the white control label rather than the quieter secondary tint.
    static let leaveLabelIsWhite: Bool = false

    /// The gap from the last element of the identity to the first box.
    static let identityToCards: CGFloat = 40

    /// The margin the page's content sits inside, on each side.
    static let sideMargin: CGFloat = 20

    /// The gap from the avatar to the name.
    static let avatarToName: CGFloat = 12

    /// The gap from the name to the member count.
    static let nameToMeta: CGFloat = 4

    /// The gap from the member count to the bio.
    static let metaToBio: CGFloat = 8

    /// The gap from the last text of the identity to the Share and Edit pills.
    static let bioToActions: CGFloat = 16

    /// The corner radius of the Share and Edit pills; half their height is a capsule.
    static let pillRadius: CGFloat = 22

    /// The outline every box is drawn with.
    static var cardShape: RoundedRectangle {
        .rect(cornerRadius: cardRadius, style: .continuous)
    }

    /// The palette settings those numbers make.
    static var settings: BleedSettings {
        BleedSettings(saturation: saturation, lightnessDark: lightnessDark, lightnessPull: lightnessPull)
    }

    /// Where the glow behind the avatar centers when the page is colored from the avatar, as a
    /// fraction of the cover.
    static let glowCenter = UnitPoint(x: 0.15, y: 0.5)
    /// The radius of that glow.
    static let glowRadius: CGFloat = 300
}

/// The image a public group's page is colored from, and whether it is drawn as the cover.
struct PublicGroupBleedSource {

    enum Kind: Equatable {
        /// The group's cover, drawn at the top of the page.
        case cover
        /// The group's avatar, which colors the page but is not drawn as a cover.
        case avatar
    }

    /// Identifies the image's pixels for the color cache.
    let key: String
    let image: UIImage
    let kind: Kind

    /// The best image there is: the cover's bytes, the cover's blurhash, then the avatar's bytes or
    /// blurhash. `nil` when the group has none of them.
    @MainActor
    init?(conversation: Conversation?, coverData: Data?, avatarData: Data?) {
        if let cover = conversation?.coverPicture {
            let coverKey = "cover-\(cover.blobID)"
            if let coverData, let image = ContactAvatarCache.shared.image(forKey: coverKey, data: coverData) {
                self.init(key: coverKey, image: image, kind: .cover)
                return
            }
            if let hash = cover.thumbnailBlurhash, let image = BlurHashCache.shared.image(for: hash) {
                self.init(key: "cover-hash-\(hash)", image: image, kind: .cover)
                return
            }
        }
        if let picture = conversation?.picture {
            let avatarKey = "avatar-\(picture.thumbnailBlobID)"
            if let avatarData, let image = ContactAvatarCache.shared.image(forKey: avatarKey, data: avatarData) {
                self.init(key: avatarKey, image: image, kind: .avatar)
                return
            }
            if let hash = picture.thumbnailBlurhash, let image = BlurHashCache.shared.image(for: hash) {
                self.init(key: "avatar-hash-\(hash)", image: image, kind: .avatar)
                return
            }
        }
        return nil
    }

    private init(key: String, image: UIImage, kind: Kind) {
        self.key = key
        self.image = image
        self.kind = kind
    }
}
