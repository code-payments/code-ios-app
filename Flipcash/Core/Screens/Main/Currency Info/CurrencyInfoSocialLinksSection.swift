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
                        Link(handle, destination: URL(string: "https://x.com/\(handle)")!)
                            .buttonStyle(.icon(.twitter))
                    case .telegram(let username):
                        Link("Telegram", destination: URL(string: "https://t.me/\(username)")!)
                            .buttonStyle(.icon(.telegram))
                    case .discord(let inviteCode):
                        Link("Discord", destination: URL(string: "https://discord.gg/\(inviteCode)")!)
                            .buttonStyle(.icon(.discord))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20) // Extend past the parent's padding
        .contentMargins(.horizontal, 20) // Inset the scroll content to match
    }
}
