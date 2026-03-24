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
                        Button("Website") {
                            UIApplication.shared.open(url)
                        }
                        .buttonStyle(.icon(.globus))
                    case .x(let handle):
                        Button(handle) {
                            UIApplication.shared.open(URL(string: "https://x.com/\(handle)")!)
                        }
                        .buttonStyle(.icon(.twitter))
                    case .telegram(let username):
                        Button("Telegram") {
                            UIApplication.shared.open(URL(string: "https://t.me/\(username)")!)
                        }
                        .buttonStyle(.icon(.chat))
                    case .discord(let inviteCode):
                        Button("Discord") {
                            UIApplication.shared.open(URL(string: "https://discord.gg/\(inviteCode)")!)
                        }
                        .buttonStyle(.icon(.chat))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -20) // Extend past the parent's padding
        .contentMargins(.horizontal, 20) // Inset the scroll content to match
    }
}
