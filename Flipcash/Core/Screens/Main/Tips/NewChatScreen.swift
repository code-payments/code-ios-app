//
//  NewChatScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI

/// What the `+` in the Chats bar opens: the kinds of chat a user can start (node 12391:77285).
struct NewChatScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var dialog: DialogItem?

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 12) {
                ChatActionRow(
                    icon: .asset(.at),
                    title: "Find Someone by Username",
                    accessibilityIdentifier: "new-chat-find-by-username"
                ) {
                    router.push(.usernameLookup)
                }

                ChatActionRow(
                    icon: .asset(.group),
                    title: "Create a New Group",
                    accessibilityIdentifier: "new-chat-private-group"
                ) {
                    Analytics.groupNewOpened(type: .private_)
                    router.push(.newPrivateGroup)
                }

                ChatActionRow(
                    icon: .asset(.currencyCoin),
                    title: "Create a New Community Chat",
                    accessibilityIdentifier: "new-chat-public-group"
                ) {
                    openCommunityChatForm()
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .navigationTitle("New Chat")
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $dialog)
    }

    /// The form's requirement needs a community currency, so a user without one is sent to buy one
    /// instead. The leaderboard is pushed onto this stack rather than routed to the Wallet tab, so
    /// the user stays in Chats.
    private func openCommunityChatForm() {
        let communityCurrencies = sessionContainer.session
            .balances(for: ratesController.rateForBalanceCurrency())
            .communityCurrencies()

        guard !communityCurrencies.isEmpty else {
            dialog = .noCommunityCurrencies {
                router.push(.discoverCurrencies)
            }
            return
        }

        Analytics.groupNewOpened(type: .community)
        router.push(.newPublicGroup)
    }
}
