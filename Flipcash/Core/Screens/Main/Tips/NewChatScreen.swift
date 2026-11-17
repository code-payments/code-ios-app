//
//  NewChatScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore
import FlipcashStore

/// What the `+` in the Chats bar opens: the kinds of chat a user can start (node 12391:77285).
/// ``NewChat/choose(_:balances:)`` decides where each row leads.
struct NewChatScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(RatesController.self) private var ratesController
    @Environment(AppRouter.self) private var router

    @State private var dialog: DialogItem?

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 12) {
                ChatActionRow(
                    icon: .asset(.group),
                    title: "Create a New Group",
                    accessibilityIdentifier: "new-chat-private-group"
                ) {
                    choose(.privateGroup)
                }

                ChatActionRow(
                    icon: .asset(.at),
                    title: "Find Someone by Username",
                    accessibilityIdentifier: "new-chat-find-by-username"
                ) {
                    choose(.findByUsername)
                }

                ChatActionRow(
                    icon: .asset(.currencyCoin),
                    title: "Create a New Community Chat",
                    accessibilityIdentifier: "new-chat-public-group"
                ) {
                    choose(.communityGroup)
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

    private func choose(_ choice: NewChat.Choice) {
        let outcome = NewChat.choose(
            choice,
            balances: sessionContainer.session.balances(for: ratesController.rateForBalanceCurrency())
        )
        switch outcome {
        case .open(let destination):
            switch choice {
            case .privateGroup: Analytics.groupNewOpened(type: .private_)
            case .communityGroup: Analytics.groupNewOpened(type: .community)
            case .findByUsername: break
            }
            router.push(Self.route(destination))
        case .noCommunityCurrencies:
            dialog = .noCommunityCurrencies {
                router.push(Self.route(NewChat.explore))
            }
        }
    }

    private static func route(_ destination: NewChat.Destination) -> AppRouter.Destination {
        switch destination {
        case .usernameLookup: .usernameLookup
        case .newPrivateGroup: .newPrivateGroup
        case .newPublicGroup: .newPublicGroup
        case .discoverCurrencies: .discoverCurrencies
        }
    }
}
