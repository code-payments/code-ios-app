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
    /// sizes one. See ``TipcardProportions/aspectRatio``.
    static let aspectRatio: CGFloat = TipcardProportions.aspectRatio

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
                        avatarImage
                            .resizable()
                            .scaledToFill()
                            .frame(width: avatarDimension, height: avatarDimension)
                            .foregroundStyle(Color.textSecondary)
                            .clipShape(Circle())

                        Text(name)
                    }
                } else {
                    Text(name)
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
                    // on the 241.6-wide card. A second type size read as an
                    // afterthought next to Figma and Android.
                    .font(.default(size: nameFontSize, weight: .medium))
                    .foregroundStyle(Color.textMain)
                    .opacity(TipcardProportions.subtitleOpacity)
                    .padding(.top, size.width * TipcardProportions.subtitleGapFraction)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(tintOpacity).background(BackdropBlur(radius: 20)))
        .clipShape(RoundedRectangle(cornerRadius: size.width * TipcardProportions.cornerRadiusFraction, style: .continuous))
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
        size.width * TipcardProportions.nameFraction
    }

    private var codeDimension: CGFloat {
        size.width * 0.68
    }

    private var avatarDimension: CGFloat {
        size.width * 0.09
    }
}
