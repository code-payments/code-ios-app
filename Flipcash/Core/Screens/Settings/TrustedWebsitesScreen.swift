//
//  TrustedWebsitesScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI

/// Lists the hosts that open without the "You're Leaving Flipcash" warning, each removable in one tap.
struct TrustedWebsitesScreen: View {

    @Environment(TrustedWebsites.self) private var trustedWebsites

    private let insets = EdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)

    var body: some View {
        Background(color: .backgroundMain) {
            if trustedWebsites.entries.isEmpty {
                VStack(spacing: 8) {
                    Text("No Trusted Websites")
                        .font(.appTextMedium)
                        .foregroundStyle(.textMain)
                    Text("Skip the “You're Leaving Flipcash” warning for a website by checking “Don't ask again” when you open its link")
                        .font(.appTextSmall)
                        .foregroundStyle(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(trustedWebsites.entries) { entry in
                            entryRow(entry)
                            Divider()
                                .overlay(Color.rowSeparator)
                        }

                        Text("Links to these sites open without the “You're Leaving Flipcash” warning. Each entry is an exact match: x.com does not cover mail.x.com.")
                            .font(.appTextSmall)
                            .foregroundStyle(.textSecondary)
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .navigationTitle("Trusted Websites")
        .toolbarTitleDisplayMode(.inline)
    }

    private func entryRow(_ entry: TrustedWebsites.Entry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.host)
                    .font(.appTextMedium)
                    .foregroundStyle(.textMain)
                Text("Added \(entry.addedAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.appTextSmall)
                    .foregroundStyle(.textSecondary)
            }
            Spacer()
            Button("Remove") {
                trustedWebsites.remove(entry.host)
            }
            .font(.appTextMedium)
            .foregroundStyle(.textError)
            .accessibilityIdentifier("trusted-website-remove-\(entry.host)")
        }
        .padding(insets)
    }
}
