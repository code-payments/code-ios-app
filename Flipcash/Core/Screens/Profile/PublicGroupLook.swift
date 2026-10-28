//
//  PublicGroupLook.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The tuned numbers of the public group profile's cover-colored page.
enum PublicGroupLook {

    /// How strongly the cover's own color is boosted before it becomes the page.
    static var saturation: Double { Tuner.shared.value("Profile/Public/Saturation", default: 1.2, in: 0...2, step: 0.01, unit: .multiplier) } // LOCAL-TUNER

    /// The OKLab lightness the page is pulled toward.
    static var lightnessDark: Double { Tuner.shared.value("Profile/Public/L dark", default: 0.1, in: 0...0.4, step: 0.01) } // LOCAL-TUNER

    /// How far toward ``lightnessDark`` the cover's color moves.
    static var lightnessPull: Double { Tuner.shared.value("Profile/Public/Pull", default: 0.6, in: 0...1, step: 0.01) } // LOCAL-TUNER

    /// The length of the melt from the cover into the page.
    static var fadeHeight: CGFloat { Tuner.shared.value("Profile/Public/Fade height", default: CGFloat(183), in: 0...320, step: 1, unit: .points) } // LOCAL-TUNER

    /// The cover's height from the top of the screen, under the status and navigation bars.
    static var coverHeight: CGFloat { Tuner.shared.value("Profile/Public/Cover height", default: CGFloat(274), in: 160...420, step: 1, unit: .points) } // LOCAL-TUNER

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
