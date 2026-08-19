//
//  TokenIcon.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// A circular currency logo — the remote token image when available, a monogram
/// fallback otherwise. Named to match Android's `TokenIcon`. Mirrors
/// `ActivityRow`'s coin rendering, factored out so the Convert destination
/// selector and picker share it.
struct TokenIcon: View {
    let url: URL?
    let monogramID: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                RemoteImage(url: url)
            } else {
                ContactAvatarView(id: monogramID, displayName: "", size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// A token's circular logo followed by its name. Named to match Android's
/// `TokenIconWithName`; used by the Convert destination selector and picker.
struct TokenIconWithName: View {
    let url: URL?
    let monogramID: String
    let name: String
    var iconSize: CGFloat = 24
    var font: Font = .appTextMedium

    var body: some View {
        HStack(spacing: 8) {
            TokenIcon(url: url, monogramID: monogramID, size: iconSize)
            Text(name)
                .font(font)
                .foregroundStyle(Color.textMain)
        }
    }
}
