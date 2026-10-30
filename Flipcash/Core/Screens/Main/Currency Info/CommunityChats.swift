//
//  CommunityChats.swift
//  Flipcash
//
//  Top Community Chats on Currency Info: a three-row preview, a "View All" screen, and the
//  ranking explainer.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The text and visibility rules for community chats, apart from the views so Android's matching
/// ones can be checked against them.
nonisolated enum CommunityChats {

    /// How many chats the section on Currency Info shows before "View All".
    static let previewCount = 3

    /// The section hides when the call returned nothing or failed (both leave the list empty).
    static func preview(_ chats: [Conversation]) -> [Conversation] {
        Array(chats.prefix(previewCount))
    }

    /// "$10,840 of Jeffy held by 44 members". Without a holdings summary the amount drops out and
    /// the row says who is in it.
    static func subtitle(amount: String?, currencyName: String, memberCount: UInt64) -> String {
        let members = memberCount == 1 ? "1 member" : "\(memberCount) members"
        guard let amount else { return members }
        return "\(amount) of \(currencyName) held by \(members)"
    }

    /// Holdings valued on the curve carry a sub-cent remainder, which would keep a whole-dollar
    /// figure from dropping its ".00". Round to the currency's cents first.
    static func holdingsText(_ amount: FiatAmount) -> String {
        amount.roundedToSmallestUnit().formattedDroppingZeroFraction()
    }

    static let rankingTitle = "How Chats Are Ranked"

    static func rankingMessage(currencyName: String) -> String {
        "Chats are ranked by the total amount of \(currencyName) held by their members. Chats with higher combined holdings appear higher"
    }
}

struct CommunityChatRow: View {

    @Environment(SessionContainer.self) private var sessionContainer

    let chat: Conversation
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            CommunityRowCard(title: chat.title ?? "", subtitle: subtitle, showsChevron: true) {
                ContactAvatarView(
                    id: chat.id.description,
                    displayName: chat.title ?? "",
                    imageData: sessionContainer.profileAvatars.data(for: .chat(chat.id)),
                    blurhash: chat.picture?.thumbnailBlurhash,
                    size: 42
                )
            }
        }
        .buttonStyle(.plain)
        .task(id: chat.id) {
            await sessionContainer.profileAvatars.load(.chat(chat.id), picture: chat.picture)
        }
    }
}

/// The card both community rows draw: a 42pt avatar, a title over an optional subtitle, and an
/// optional chevron. Without a subtitle the title sits centred.
struct CommunityRowCard<Avatar: View>: View {

    let title: String
    let subtitle: String?
    let showsChevron: Bool
    @ViewBuilder let avatar: () -> Avatar

    var body: some View {
        HStack(spacing: 12) {
            avatar()
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 67)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.backgroundRow))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// "Top Community Chats", its info button and "View All", over the first three rows. Draws
/// nothing when there are no chats.
struct CommunityChatsSection: View {

    let chats: [Conversation]
    let currencyName: String
    let subtitle: (Conversation) -> String
    let onSelect: (Conversation) -> Void
    let onInfo: () -> Void
    let onViewAll: () -> Void

    var body: some View {
        if !chats.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Text("Top Community Chats")
                        .font(.default(size: 19, weight: .bold))
                        .foregroundStyle(Color.textMain)
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    .accessibilityLabel("How chats are ranked")
                    Spacer(minLength: 0)
                    Button("View All", action: onViewAll)
                        .font(.default(size: 13, weight: .medium))
                        .foregroundStyle(Color.textMain)
                }
                .frame(minHeight: 28)
                VStack(spacing: 10) {
                    ForEach(CommunityChats.preview(chats), id: \.id) { chat in
                        CommunityChatRow(chat: chat, subtitle: subtitle(chat)) { onSelect(chat) }
                    }
                }
            }
        }
    }
}

/// Every chat the call returned, in the server's order.
struct TopCommunityChatsScreen: View {

    let chats: [Conversation]
    let subtitle: (Conversation) -> String
    let onSelect: (Conversation) -> Void

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(chats, id: \.id) { chat in
                        CommunityChatRow(chat: chat, subtitle: subtitle(chat)) { onSelect(chat) }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Top Community Chats")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The "View All" destination: loads the same ranked list and opens a chat's group profile.
struct TopCommunityChatsDestination: View {

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router
    @Environment(ConversationController.self) private var conversationController

    let mint: PublicKey
    @State private var viewModel: CurrencyInfoViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TopCommunityChatsScreen(
                    chats: viewModel.communityChats,
                    subtitle: viewModel.communitySubtitle(for:),
                    onSelect: { chat in
                        Analytics.tokenInfoCommunityChatTapped(mint: mint)
                        conversationController.hold(chat)
                        router.push(.chatProfile(chat.id, origin: .featuredGroup))
                    }
                )
            } else {
                Background(color: .backgroundMain) { Color.clear }
            }
        }
        .task {
            let model = CurrencyInfoViewModel(
                mint: mint,
                session: sessionContainer.session,
                database: sessionContainer.database,
                ratesController: sessionContainer.ratesController
            )
            viewModel = model
            await model.loadMintMetadata()
            await model.loadCommunityChats()
        }
    }
}
