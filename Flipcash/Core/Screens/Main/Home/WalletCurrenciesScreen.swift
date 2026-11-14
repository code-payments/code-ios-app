//
//  WalletCurrenciesScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Every currency the wallet holds, behind "N currencies" on the Money screen,
/// as today's wallet draws them: a ``TokenCardStack``, where tapping a card
/// opens its page over the deck and closing puts it back.
///
/// The system bar stays hidden, as it does over today's wallet. The deck and the
/// page it opens are placed against the top of the safe area, and showing the
/// bar here would move that edge down by the bar's height; hiding it for the
/// page, as Money does, would move the deck under the travelling card. The
/// back button and title are drawn instead.
struct WalletCurrenciesScreen: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(\.dismiss) private var dismiss

    /// One card per currency, resolved off the body (a DB read per token).
    /// `nil` until first read, so the empty message never flashes ahead of it.
    @State private var cards: [TokenCardData]?
    /// The opened card's transition.
    private var deck = WalletCardDeck()
    /// Used to push the cards below the opened one off the screen.
    @State private var containerSize: CGSize = .zero
    /// Where the opened card's page lays out from.
    @State private var safeArea: EdgeInsets = .init()

    /// Shared with the page the card opens, as today's wallet shares its own.
    @Namespace private var cardNamespace

    /// The drawn bar: as tall as the page's chrome, which takes its place when
    /// a card opens, so its close box lands where the back button was.
    private static let headerHeight: CGFloat = 44
    /// Where the deck starts, and where its cards pile up as it scrolls.
    private static let deckTop: CGFloat = headerHeight + 16

    private var rate: Rate { ratesController.rateForBalanceCurrency() }

    var body: some View {
        Background(color: .backgroundMain) {
            content
        }
        .overlay(alignment: .top) { header }
        .walletCardPage(deck) { deck.close(resumingFrom: $0) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
        .toolbar(.hidden, for: .navigationBar)
        // The page is laid over this screen, not pushed onto it, so going back
        // would pop the screen out from under it.
        .navigationBarBackButtonHidden(deck.pageIsBuilt)
        .environment(\.walletCardNamespace, cardNamespace)
        .onAppear { refresh() }
        .onChange(of: session.balances) { _, _ in refresh() }
        .onChange(of: rate) { _, _ in refresh() }
    }

    @ViewBuilder private var content: some View {
        if let cards, cards.isEmpty {
            Text("No currencies yet")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .accessibilityIdentifier("wallet-currencies-empty")
        } else if let cards {
            ScrollView(.vertical, showsIndicators: false) {
                TokenCardStack(
                    items: cards,
                    pinInset: Self.deckTop,
                    namespace: cardNamespace,
                    expandingMint: deck.expandingMint,
                    expansionProgress: deck.expansionProgress,
                    containerHeight: containerSize.height,
                    hiddenMint: deck.hiddenMint,
                    openTopInset: WalletCardGeometry.openCardTopInset,
                    openExtraOffset: deck.releasedPullOffset,
                    onCardTap: open
                )
                .padding(.top, Self.deckTop)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            // Locked while the page is up, as on today's wallet.
            .scrollDisabled(deck.pageIsBuilt)
        }
    }

    private var header: some View {
        ZStack {
            Text("Currencies")
                .font(.appTitle)
                .foregroundStyle(Color.textMain)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textMain)
                        .frame(width: Self.headerHeight, height: Self.headerHeight)
                        // Hit-test the whole target, not just the glyph.
                        .contentShape(Circle())
                        .modifier(CircleGlass())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("wallet-currencies-back")

                Spacer(minLength: 0)
            }
        }
        .frame(height: Self.headerHeight)
        .padding(.horizontal, 16)
        // Clears with the deck as a card opens; the page draws its own chrome.
        .opacity(deck.deckOpacity)
    }

    private func open(_ item: TokenCardData, currentTop: CGFloat) {
        Analytics.tokenInfoOpened(from: .openedFromWallet, mint: item.mint)
        deck.open(item.mint, currentTop: currentTop, safeAreaTop: safeArea.top)
    }

    private func refresh() {
        let balances = Session.walletCardBalances(from: session.balances(for: rate))
        cards = TokenCardData.walletCards(for: balances, session: session, rate: rate)
    }
}
