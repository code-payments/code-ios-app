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
    /// sizes one.
    static let aspectRatio: CGFloat = 1.16

    /// Explicit because a rendered tree has no container to size against.
    let size: CGSize
    let name: String
    let avatar: UIImage?
    let codeData: Data

    var body: some View {
        VStack(spacing: 0) {
            CodeView(data: codeData)
                .foregroundStyle(Color.white)
                .frame(width: codeDimension, height: codeDimension)

            HStack(spacing: 8) {
                Text("Tip")

                avatarImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: avatarDimension, height: avatarDimension)
                    .foregroundStyle(Color.textSecondary)
                    .clipShape(Circle())

                Text(name)
                    .lineLimit(1)
            }
            .font(.appDisplayXS)
            .foregroundStyle(Color.textMain)
            .padding(.top, size.height * 0.06)
        }
        .frame(width: size.width, height: size.height)
        .background(Color(white: 0.11))
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

    private var codeDimension: CGFloat {
        size.width * 0.68
    }

    private var avatarDimension: CGFloat {
        size.width * 0.09
    }
}
