//
//  TipcardView.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// The shareable tipcard: a scannable code over the owner's name and photo.
///
/// Takes only resolved values — no environment, no URLs, no async loading — so
/// the same view renders on screen and through `ImageRenderer` for export.
struct TipcardView: View {

    /// The card's height-to-width proportion, shared by every surface that
    /// sizes one. From Figma's 269 x 333 card, which holds that proportion both
    /// on the You page (node 9276:4641) and full screen (node 9277:121417).
    static let aspectRatio: CGFloat = 333.0 / 269.0

    /// The name's size as a fraction of the card's width. Figma draws the name
    /// at 17 on the 269-wide card and scales it with the card, so the 302-wide
    /// full-screen card gets 19.1 (node 9277:121421) and the 242-wide You-page
    /// card 15.3 (node 9276:4645). A fixed size instead left the name looking
    /// oversized on the small card and undersized on the big one.
    static let nameFraction: CGFloat = 17.0 / 269.0

    /// The gap between the name and the subtitle, as a fraction of the card's
    /// width so it scales with the type. From node 9443:7991's 4 on the
    /// 241.6-wide card.
    static let subtitleGapFraction: CGFloat = 4.0 / 241.636

    /// Explicit because a rendered tree has no container to size against.
    let size: CGSize
    let name: String
    let avatar: UIImage?
    let codeData: Data

    /// Opacity of the black tint over the frosted backdrop, so callers can tune
    /// contrast against different surfaces (share sheet vs. live camera).
    var tintOpacity: Double = 0.72

    /// The profile photo is intentionally omitted from the card for now, so the
    /// avatar is gated off by default. Kept as a flag (rather than deleted) so
    /// re-enabling it is a one-line change once the product decision reverts.
    var includePhoto: Bool = false

    /// An optional second line under the name — the owner's `@handle` once they
    /// have claimed one. Cards without a username pass nil and keep the name
    /// sitting where it always has.
    var subtitle: String?

    var body: some View {
        VStack(spacing: 0) {
            CodeView(data: codeData)
                .foregroundStyle(Color.white)
                .frame(width: codeDimension, height: codeDimension)

            Group {
                if includePhoto {
                    HStack(spacing: 8) {
                        Text("Tip")

                        avatarImage
                            .resizable()
                            .scaledToFill()
                            .frame(width: avatarDimension, height: avatarDimension)
                            .foregroundStyle(Color.textSecondary)
                            .clipShape(Circle())

                        Text(name)
                    }
                } else {
                    // Set as one string rather than two views in a stack: with
                    // no avatar between them the stack's gap stands in for the
                    // space, and at this size it is half again as wide as the
                    // font's own — enough to read as a double space.
                    Text("Tip \(name)")
                }
            }
            // Long names get a second line before being cut, rather than being
            // truncated on the first.
            .lineLimit(2)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .padding(.horizontal, size.width * 0.08)
            .font(.default(size: nameFontSize, weight: .bold))
            .foregroundStyle(Color.textMain)
            .padding(.top, size.height * 0.06)

            if let subtitle {
                Text(subtitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, size.width * 0.08)
                    // Same size as the name — node 9443:7991 draws both at 15
                    // on the 241.6-wide card. Medium rather than bold, at half
                    // opacity, is what separates the handle from the name; a
                    // second type size read as an afterthought next to Figma
                    // and Android.
                    .font(.default(size: nameFontSize, weight: .medium))
                    .foregroundStyle(Color.textMain)
                    .opacity(0.5)
                    .padding(.top, size.width * Self.subtitleGapFraction)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(tintOpacity).background(BackdropBlur(radius: 20)))
        .clipShape(RoundedRectangle(cornerRadius: size.width * 0.08, style: .continuous))
    }

    /// The system avatar placeholder stands in when the photo isn't available,
    /// so the card never renders with a hole in it.
    private var avatarImage: Image {
        if let avatar {
            Image(uiImage: avatar)
        } else {
            Image(systemName: "person.crop.circle.fill")
        }
    }

    private var nameFontSize: CGFloat {
        size.width * Self.nameFraction
    }

    private var codeDimension: CGFloat {
        size.width * 0.68
    }

    private var avatarDimension: CGFloat {
        size.width * 0.09
    }
}
