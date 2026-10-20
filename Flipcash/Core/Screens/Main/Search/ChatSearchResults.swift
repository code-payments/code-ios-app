//
//  ChatSearchResults.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// The results for the model's query under its chip.
struct ChatSearchResults: View {

    let model: ChatSearchModel
    let onOpenChat: (Conversation) -> Void
    let onOpenMessage: (ChatSearchMessageHit) -> Void
    let onOpenLink: (ChatSearchLink) -> Void
    let onOpenCurrency: (MintMetadata) -> Void

    private var results: ChatSearchModel.Results { model.results }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            switch model.scope {
            case .all:
                allSections
            case .chats:
                chatRows(results.chats)
            case .currencies:
                currencyGrid(results.currencies)
            case .messages:
                messageRows(results.messages)
            case .links:
                linkRows(results.links)
            }
        }
        .padding(.bottom, 16)
        .overlay(alignment: .top) {
            if isEmpty {
                Text("No results")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 80)
            }
        }
    }

    private var isEmpty: Bool {
        switch model.scope {
        case .all:        results.chats.isEmpty && results.currencies.isEmpty && results.messages.isEmpty
        case .chats:      results.chats.isEmpty
        case .currencies: results.currencies.isEmpty
        case .messages:   results.messages.isEmpty
        case .links:      results.links.isEmpty
        }
    }

    @ViewBuilder
    private var allSections: some View {
        let limit = ChatSearchModel.allSectionLimit
        if !results.chats.isEmpty {
            SectionHeader(title: "Chats", scope: .chats, model: model)
            chatRows(Array(results.chats.prefix(limit)))
        }
        if !results.currencies.isEmpty {
            SectionHeader(title: "Currencies", scope: .currencies, model: model)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(results.currencies, id: \.address) { mint in
                        currencyCard(mint)
                            .frame(width: 170)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        if !results.messages.isEmpty {
            SectionHeader(title: "Messages", scope: .messages, model: model)
            messageRows(Array(results.messages.prefix(limit)))
        }
    }

    private func chatRows(_ chats: [Conversation]) -> some View {
        ForEach(chats) { conversation in
            // The row's insets come from `listRowInsets`, which a stack ignores.
            TipConversationRow(conversation: conversation) { onOpenChat(conversation) }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
    }

    private func messageRows(_ hits: [ChatSearchMessageHit]) -> some View {
        ForEach(hits) { hit in
            MessageHitRow(hit: hit, model: model) { onOpenMessage(hit) }
        }
    }

    private func linkRows(_ links: [ChatSearchLink]) -> some View {
        ForEach(links) { link in
            LinkRow(link: link, subtitle: linkSubtitle(link)) { onOpenLink(link) }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
    }

    private func currencyGrid(_ mints: [MintMetadata]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(mints, id: \.address) { mint in
                currencyCard(mint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func currencyCard(_ mint: MintMetadata) -> some View {
        let sharer = model.currencySharers[mint.address]
        let sharedBy = sharer.flatMap { model.name(of: $0.senderID, in: $0.conversationID) }
        return Button { onOpenCurrency(mint) } label: {
            SearchCurrencyCard(mint: mint, sharedBy: sharedBy)
        }
        .buttonStyle(.plain)
    }

    /// "Shared by Jeff", "Shared in Jeffy Holders" for a group, or "Shared by you", then the date.
    private func linkSubtitle(_ link: ChatSearchLink) -> String {
        let sender = model.name(of: link.senderID, in: link.conversationID)
        let isGroup = model.isGroup(link.conversationID)
        let lead: String
        if sender == "you" {
            lead = "Shared by you"
        } else if isGroup, let chat = model.chatName(for: link.conversationID) {
            lead = "Shared in \(chat)"
        } else if let sender {
            lead = "Shared by \(sender)"
        } else {
            lead = "Shared"
        }
        return "\(lead) · \(link.date.formattedRelatively())"
    }
}

// MARK: - Section header -

private struct SectionHeader: View {
    let title: String
    let scope: ChatSearchScope
    let model: ChatSearchModel

    var body: some View {
        HStack {
            Text(title)
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button("See all") {
                model.scope = scope
            }
            .font(.appTextMedium)
            .foregroundStyle(Color.textMain)
            .accessibilityIdentifier("chat-search-see-all-\(title)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Message hit -

private struct MessageHitRow: View {

    let hit: ChatSearchMessageHit
    let model: ChatSearchModel
    let onTap: () -> Void

    @Environment(ConversationController.self) private var conversationController

    var body: some View {
        let conversation = conversationController.conversation(withID: hit.conversationID)
        let title = model.chatName(for: hit.conversationID) ?? ""
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                if let conversation {
                    ChatSearchAvatar(conversation: conversation)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.appTextMedium)
                            .foregroundStyle(Color.textMain)
                            .lineLimit(1)
                        Spacer()
                        Text(hit.date.formattedRelatively())
                            .font(.appTextSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Text(preview)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The text, led by the sender's name in a group.
    private var preview: String {
        guard model.isGroup(hit.conversationID), let sender = model.name(of: hit.senderID, in: hit.conversationID) else {
            return hit.text
        }
        return "\(sender == "you" ? "You" : sender): \(hit.text)"
    }
}

// MARK: - Link -

private struct LinkRow: View {

    let link: ChatSearchLink
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.backgroundRow)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "link")
                            .foregroundStyle(Color.textSecondary)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.host)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Text(link.title ?? link.url.absoluteString)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Currency card -

/// A currency on its bill gradient: market cap, the week's change, new members, and who shared it.
struct SearchCurrencyCard: View {

    let mint: MintMetadata
    let sharedBy: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                RemoteImage(url: mint.imageURL)
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                Text(mint.name)
                    .font(.appTextMedium)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            if let marketCap = SearchCurrencyCard.marketCap(of: mint) {
                Text(marketCap, format: .compactCurrency(code: .usd))
                    .font(.appDisplaySmall)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let weekly = SearchCurrencyCard.weeklyChange(of: mint) {
                Text(weekly)
                    .font(.appTextSmall)
            }
            if let members = SearchCurrencyCard.newMembers(of: mint) {
                Text(members)
                    .font(.appTextSmall)
            }
            if let sharedBy {
                Text("Shared by \(sharedBy)")
                    .font(.appTextSmall)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Color.white)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .background(gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var gradient: LinearGradient {
        let parsed = mint.billColors.compactMap(Color.init(hex:))
        let stops: [Color] = switch parsed.count {
        case 0:  [Color.backgroundSecondary, Color.backgroundSecondary]
        case 1:  [parsed[0], parsed[0]]
        default: parsed
        }
        return LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
    }

    /// Discover's market cap, else the bonding-curve estimate; nil when neither is above zero.
    nonisolated static func marketCap(of mint: MintMetadata) -> Double? {
        if let current = mint.marketCapMetrics?.currentMarketCap, current > 0 { return current }
        if let estimate = mint.launchpadMetadata?.marketCap, estimate > 0 { return estimate }
        return nil
    }

    /// "+$3.1K this week", from Discover's weekly market-cap change.
    nonisolated static func weeklyChange(of mint: MintMetadata) -> String? {
        guard let weekly = mint.marketCapMetrics?.marketCapDeltas.first(where: { $0.range == .lastWeek }) else { return nil }
        let sign = weekly.delta >= 0 ? "+" : ""
        return "\(sign)\(weekly.delta.formatted(.compactCurrency(code: .usd))) this week"
    }

    /// "+41 members", from Discover's weekly holder change; nil unless members were gained.
    nonisolated static func newMembers(of mint: MintMetadata) -> String? {
        guard let weekly = mint.holderMetrics?.holderDeltas.first(where: { $0.range == .lastWeek }), weekly.delta > 0 else { return nil }
        return "+\(weekly.delta.formatted(.number.notation(.compactName))) \(weekly.delta == 1 ? "member" : "members")"
    }
}
