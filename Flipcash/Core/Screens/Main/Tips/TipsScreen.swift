//
//  TipsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The Tips sheet's root: the tip conversations once a profile exists, the
/// invitation to create one until then.
struct TipsScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer

    /// The v2 Chats tab: a large flush "Chats" title and no inline tip-card
    /// button (the tip card has its own tab). Defaults to `false` — the v1 Tips
    /// sheet keeps its inline nav-bar title and "Show My Tip Card" button.
    var isEmbedded: Bool = false

    var body: some View {
        // v2's Chats tab is chats, whatever the profile says. A name-less
        // account can still send tips, so it can still hold conversations —
        // swapping the tab out for a setup prompt hid them, and hid the "No
        // Chats Yet" empty state behind a second copy of the tip-card
        // invitation the tip-card tab already makes. v1's sheet keeps the
        // intro: it is that flow's only door into profile creation.
        if isEmbedded || sessionContainer.session.profile?.isTippable == true {
            TipConversationsScreen(isEmbedded: isEmbedded)
        } else {
            TipsIntroScreen(isEmbedded: isEmbedded)
        }
    }
}

// MARK: - Chats title -

/// The v2 large, flush start-aligned "Chats" tab title (Android parity —
/// `screenTitleLarge` / `appTitleLarge`), with the new-chat button beside it.
struct ChatsTabTitle: View {

    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(spacing: 0) {
            Text("Chats")
                .font(.appTitleLarge)
                .foregroundStyle(Color.textMain)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                router.push(.usernameLookup)
            } label: {
                // The design draws a 44pt circle (node 9443:8560). On iOS 26
                // `.buttonStyle(.glass)` pads outside the label, so the label
                // is 32 and the glass reaches 44; the fallback style draws the
                // circle at the label's own bounds, so there it is 44 already.
                if #available(iOS 26, *) {
                    Image.system(.plus)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .frame(width: 32, height: 32)
                } else {
                    Image.system(.plus)
                        .font(.appTextLarge)
                        .foregroundStyle(Color.textMain)
                        .frame(width: 44, height: 44)
                }
            }
            .liquidGlassButtonStyle(shape: .circle)
            .accessibilityLabel("New chat")
            .accessibilityIdentifier("new-chat-button")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - TipsIntroScreen -

private struct TipsIntroScreen: View {

    @Environment(AppRouter.self) private var router

    let isEmbedded: Bool

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                if isEmbedded {
                    ChatsTabTitle()
                }

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
        }
        .navigationTitle(isEmbedded ? "" : "Tips")
        .toolbar(isEmbedded ? .hidden : .automatic, for: .navigationBar)
        .toolbarTitleDisplayMode(.inline)
    }
}
