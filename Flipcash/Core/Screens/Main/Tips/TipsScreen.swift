//
//  TipsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The `.tips` stack's root: the tip conversations, or the invitation to create
/// a profile when the stack was opened to ask for one.
struct TipsScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer

    /// Hosted by the Chats tab rather than presented as the `.tips` sheet.
    /// Defaults to `false` — `TipFlow` presents the sheet only to ask for a
    /// profile, so there it leads with ``TipsIntroScreen``.
    var isEmbedded: Bool = false

    var body: some View {
        // The Chats tab is chats, whatever the profile says. A name-less
        // account can still send tips, so it can still hold conversations —
        // swapping the tab out for a setup prompt hid them, and hid the "No
        // Chats Yet" empty state behind a second copy of the tip-card
        // invitation the tip-card tab already makes. The sheet keeps the
        // intro: it is that flow's only door into profile creation.
        if isEmbedded || sessionContainer.session.profile?.isTippable == true {
            TipConversationsScreen()
        } else {
            TipsIntroScreen()
        }
    }
}

// MARK: - TipsIntroScreen -

/// The `.tips` sheet's profile-creation invitation. The Chats tab shows
/// conversations whatever the profile says, so it never reaches this.
private struct TipsIntroScreen: View {

    @Environment(AppRouter.self) private var router

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Spacer()

                // The tab-bar asset carries a heavier stroke tuned for 40pt;
                // at this size it needs the lighter one.
                Image(.Icons.tipsLarge)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(Color.textMain)

                Text("Receive Tips From Everyone")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)

                Text("Add your name to receive tips")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()

                Button("Start Receiving Tips") {
                    router.push(.profileName)
                }
                .buttonStyle(.filled)
                .accessibilityIdentifier("start-receiving-tips-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Tips")
        .toolbarTitleDisplayMode(.inline)
    }
}
