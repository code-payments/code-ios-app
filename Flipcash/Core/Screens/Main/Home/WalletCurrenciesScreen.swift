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
/// The system bar shows "Currencies" and the back button, as any pushed screen
/// does, so going back hands the bar to Money's title and avatar in one
/// transition. A screen that hid its bar instead had Money's bar appear on top
/// of it for the whole back swipe.
///
/// The bar stays up while a card's page is open, so nothing in it moves: the
/// page's close goes where the back button was, and the title fades with the
/// deck. Below iOS 26 the bar is opaque and would cover the page, so there it
/// hides while the page is up, as Money's does, and the page draws its own
/// chrome where the bar was.
///
/// Hiding the bar moves the top of the safe area up by its height, on the tap,
/// while the card is leaving the deck. The deck's scroll view therefore ignores
/// that edge and is placed from fixed numbers: the bar's bottom as last measured
/// while it showed, and the status bar's inset, which the page lays out from
/// whether the bar is up or not.
struct WalletCurrenciesScreen: View {

    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController

    /// One card per currency, resolved off the body (a DB read per token).
    /// `nil` until first read, so the empty message never flashes ahead of it.
    @State private var cards: [TokenCardData]?
    /// The opened card's transition.
    private var deck = WalletCardDeck()
    /// The deck's scroll view, used to push the cards below the opened one off the screen.
    @State private var viewportHeight: CGFloat = 0
    /// The bottom of the bar, from the top of the screen, as last measured while it showed.
    @State private var barBottom: CGFloat = 0

    /// Shared with the page the card opens, as today's wallet shares its own.
    @Namespace private var cardNamespace

    /// The gap between the bar and the deck, which is also where its cards pile up as it scrolls.
    private static let deckGap: CGFloat = 16

    private var rate: Rate { ratesController.rateForBalanceCurrency() }

    /// Whether the bar stays up over a card's page. From iOS 26 the bar is clear
    /// over what scrolls under it; before that it is opaque and would cover the page.
    private static var keepsBarOverPage: Bool {
        if #available(iOS 26, *) { true } else { false }
    }

    /// Where the deck starts and its cards pile up, from the top of the screen.
    private var deckTop: CGFloat { barBottom + Self.deckGap }

    var body: some View {
        Background(color: .backgroundMain) {
            content
        }
        .walletCardPage(deck, underHostBar: Self.keepsBarOverPage) { deck.close(resumingFrom: $0) }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { top in
            // Measured while the bar shows; the deck keeps that edge while it is hidden.
            if !deck.pageIsBuilt { barBottom = top }
        }
        .navigationTitle("Currencies")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(Self.keepsBarOverPage || !deck.pageIsBuilt ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if #available(iOS 26, *) {
                // Drawn here rather than by the system so it can fade with the
                // deck as a card opens and closes, in place, instead of leaving
                // and arriving with the bar.
                ToolbarItem(placement: .principal) {
                    Text("Currencies")
                        .font(.appTitle)
                        .foregroundStyle(Color.textMain)
                        .opacity(deck.deckOpacity)
                        .accessibilityAddTraits(.isHeader)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        // The page is laid over this screen, not pushed onto it, so going back
        // would pop the screen out from under it. With the bar up, the page's
        // close takes the back button's spot.
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
                    pinInset: deckTop,
                    namespace: cardNamespace,
                    expandingMint: deck.expandingMint,
                    expansionProgress: deck.expansionProgress,
                    containerHeight: viewportHeight,
                    hiddenMint: deck.hiddenMint,
                    // The page's hero card rests this far below the status bar.
                    openTopInset: WalletCardGeometry.statusBarInset + WalletCardGeometry.openCardTopInset,
                    openExtraOffset: deck.releasedPullOffset,
                    onCardTap: open
                )
                .padding(.top, deckTop)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            // Measured from the top of the screen, which the bar does not move.
            .ignoresSafeArea(.container, edges: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            // Locked while the page is up, as on today's wallet.
            .scrollDisabled(deck.pageIsBuilt)
        }
    }

    private func open(_ item: TokenCardData, currentTop: CGFloat) {
        Analytics.tokenInfoOpened(from: .openedFromWallet, mint: item.mint)
        // The page lays out from the status bar, whether the bar stays up or hides.
        deck.open(item.mint, currentTop: currentTop, safeAreaTop: WalletCardGeometry.statusBarInset)
    }

    private func refresh() {
        let balances = Session.walletCardBalances(from: session.balances(for: rate))
        cards = TokenCardData.walletCards(for: balances, session: session, rate: rate)
    }
}
