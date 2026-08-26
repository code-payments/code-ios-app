//
//  CurrencyInfoAboutSection.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The "About" block on the currency info screen: an expand/collapse description
/// and, for community tokens, the social link chips. Split out so the copy +
/// expand/collapse behaviour stays in one place.
struct CurrencyInfoAboutSection: View {
    let description: String
    let socialLinks: [SocialLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)

            ExpandableText(description)
                .foregroundStyle(Color.textSecondary)
                .font(.appTextSmall)

            if !socialLinks.isEmpty {
                CurrencyInfoSocialLinksSection(socialLinks: socialLinks)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
