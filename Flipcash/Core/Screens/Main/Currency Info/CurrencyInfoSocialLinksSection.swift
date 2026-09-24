//
//  CurrencyInfoSocialLinksSection.swift
//  Code
//
//  Created by Raul Riera on 2026-03-24.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct CurrencyInfoSocialLinksSection: View {
    let socialLinks: [SocialLink]

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(socialLinks) { socialLink in
                    switch socialLink {
                    case .website(let url):
                        Link("Website", destination: url)
                            .buttonStyle(.icon(.globus))
                    case .x(let handle):
                        if let url = URL.socialProfile(host: "x.com", handle: handle) {
                            Link(handle, destination: url)
                                .buttonStyle(.icon(.twitter))
                        }
                    case .telegram(let username):
                        if let url = URL.socialProfile(host: "t.me", handle: username) {
                            Link("Telegram", destination: url)
                                .buttonStyle(.icon(.telegram))
                        }
                    case .discord(let inviteCode):
                        if let url = URL.socialProfile(host: "discord.gg", handle: inviteCode) {
                            Link("Discord", destination: url)
                                .buttonStyle(.icon(.discord))
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
