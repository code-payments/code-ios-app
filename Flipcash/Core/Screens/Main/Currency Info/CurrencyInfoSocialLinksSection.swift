//
//  CurrencyInfoSocialLinksSection.swift
//  Code
//
//  Created by Raul Riera on 2026-03-24.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// A link chip drawn to the design: a 17pt glyph and a regular 16pt label in a 6pt-radius tile.
/// Local to this section because the shared `IconButtonStyle` sets a bold 16pt label and an 18pt glyph.
private struct LinkChipStyle: ButtonStyle {
    let icon: Asset

    init(_ icon: Asset) { self.icon = icon }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Image.asset(icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 17, height: 17)
            configuration.label
                .lineLimit(1)
                .font(.default(size: 16, weight: .regular))
                .foregroundStyle(Color.textMain)
        }
        .opacity(configuration.isPressed ? 0.6 : 1.0)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.1))
        .clipShape(.rect(cornerRadius: 6))
    }
}

struct CurrencyInfoSocialLinksSection: View {
    let socialLinks: [SocialLink]

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(socialLinks) { socialLink in
                    switch socialLink {
                    case .website(let url):
                        Link("Website", destination: url)
                            .buttonStyle(LinkChipStyle(.globus))
                    case .x(let handle):
                        if let url = URL.socialProfile(host: "x.com", handle: handle) {
                            Link("@\(handle)", destination: url)
                                .buttonStyle(LinkChipStyle(.twitter))
                        }
                    case .telegram(let username):
                        if let url = URL.socialProfile(host: "t.me", handle: username) {
                            Link("Telegram", destination: url)
                                .buttonStyle(LinkChipStyle(.telegram))
                        }
                    case .discord(let inviteCode):
                        if let url = URL.socialProfile(host: "discord.gg", handle: inviteCode) {
                            Link("Discord", destination: url)
                                .buttonStyle(LinkChipStyle(.discord))
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20) // Extend past the parent's padding
        .contentMargins(.horizontal, 20) // Inset the scroll content to match
    }
}

extension URL {

    /// `https://<host>/<handle>` for a handle from a token's metadata, or `nil` when there is no
    /// handle or it would span more than one path segment.
    ///
    /// The token's creator writes the handle. Set as a path through `URLComponents`, a `?`, `#`, or
    /// space is percent-encoded rather than starting a query or fragment, so the link stays on the
    /// profile it names.
    nonisolated static func socialProfile(host: String, handle: String) -> URL? {
        guard !handle.isEmpty, !handle.contains("/") else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/\(handle)"
        return components.url
    }
}
