//
//  CurrencyInfoContentV2.swift
//  Flipcash
//
//  The currency info layout: a hero bill card, inline Give / Convert /
//  Withdraw (or Get) tiles, a per-token Recent preview, the reused market-cap
//  chart, the About block, and a created-at footer.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// Softens the top scroll edge on iOS 26+ so content fades under the toolbar
/// rather than being clipped by the system's hard edge line.
private struct SoftTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

/// Marks the hero card as the morph destination for the wallet's tapped card.
/// Without a namespace (pushed hosting, deep links) the card renders plainly.
private struct HeroCardMatch: ViewModifier {
    let mint: PublicKey
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: mint, in: namespace)
        } else {
            content
        }
    }
}

struct CurrencyInfoContentV2: View {
    let metadata: StoredMintMetadata
    let decodedMetadata: MintMetadata
    let viewModel: CurrencyInfoViewModel
    let ratesController: RatesController
    let marketCapController: MarketCapController
    let session: Session

    /// Give — owned community tokens only.
    let onGive: () -> Void
    /// Convert — sells this (non-USDF) currency into a chosen destination.
    let onConvert: () -> Void
    /// Get — routes to the buy flow for unowned tokens.
    let onBuy: () -> Void
    /// Withdraw — the existing flow, pre-selected to this currency.
    let onWithdraw: () -> Void
    let onShowTransactionHistory: () -> Void
    /// Fires when the hero card's title scrolls out from under the toolbar, so
    /// the screen can reveal its own title.
    let onScrolledPastTitle: (Bool) -> Void
    /// How far the content has been pulled past its top, and how far it had been
    /// pulled when the finger lifted. A host that can be dismissed uses the
    /// second to decide whether the pull was a close.
    var onPulledDown: (CGFloat) -> Void = { _ in }
    var onPullEnded: (CGFloat) -> Void = { _ in }
    /// False when the host already shows the card (the wallet keeps it on screen
    /// while the detail rises beneath it), so it is not drawn twice.
    var showsHeroCard: Bool = true
    /// Displaces the hero card from its resting slot while the host animates the
    /// screen in — the wallet starts it over the deck and drives it to zero.
    var heroOffset: CGFloat = 0
    /// Everything except the hero card. The card is the one element carried over
    /// from the wallet, so it stays at full strength while the screen behind it
    /// arrives.
    var contentOpacity: Double = 1
    /// True while the page is animating in: the chart build and the activity
    /// read are held back so they cannot stutter the transition.
    var defersHeavyContent: Bool = false

    private static let recentPreviewCount = 3
    /// Scroll distance that puts the hero card's title row behind the toolbar.
    private static let titleHandoffOffset: CGFloat = 52

    /// The live pull distance, kept so the phase change can report the value the
    /// finger lifted at — the geometry callback has stopped firing by then.
    @State private var pullDistance: CGFloat = 0
    /// Whether the overscroll being reported is coming from a finger rather than
    /// from momentum after one has left.
    @State private var isDragging = false
    /// Whether that finger went down on the card. The card is the handle for
    /// the dismissal — dragging the page below it should only ever scroll.
    @State private var touchBeganOnCard = false
    /// Where the card is on screen, so the above can be worked out.
    @State private var heroFrame: CGRect = .zero
    /// Whether this drag's origin has been judged yet. It is settled once, at
    /// the start: the card travels down under the finger, so re-testing the
    /// (fixed) start point against its moving frame flips the answer to false
    /// part-way through the drag.
    @State private var hasJudgedOrigin = false
    /// Whether this drag ever moved the screen. Whatever the origin, a drag
    /// that scrubbed has to be ended, or the screen is left part-dismissed.
    @State private var didScrub = false

    private var isUSDF: Bool { metadata.mint == .usdf }
    private var isOwned: Bool { viewModel.balance.hasDisplayableValue }


    /// Shared with the wallet card stack when hosted as an overlay, so the
    /// tapped card morphs into the hero card above.
    @Environment(\.walletCardNamespace) private var cardNamespace

    var body: some View {
        ScrollView {
            // Horizontal insets are applied per section rather than to the whole
            // stack: the market-cap chart bleeds edge to edge, and cancelling an
            // outer inset with negative padding makes that row wider than the
            // viewport, which turns the scroll view horizontally scrollable.
            VStack(spacing: 24) {
                // The slot is always reserved: while the wallet's card is still
                // in the air this is empty, but dropping it from the layout
                // shifts everything below up and then jumps it back down when
                // the card lands.
                Group {
                    if showsHeroCard {
                        heroCard
                    } else {
                        Color.clear.frame(height: WalletCardGeometry.cardHeight)
                    }
                }
                .padding(.horizontal, 20)
                // Deliberately outside the fade below: this is the card the
                // wallet was already showing, so it is continuous rather than
                // something that arrives.
                .offset(y: heroOffset)
                // Its position on screen, so a drag can be tested against it.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { heroFrame = $0 }

                Group {
                    actionTiles
                    .padding(.horizontal, 20)

                // Everything below is laid out and shown from the first frame,
                // so the page arrives complete rather than in stages. Nothing
                // here is gated on loading: the activity read is quick and runs
                // off the main thread, and the market-cap section reserves its
                // full height around a placeholder plot. Revealing these later —
                // even all at once — reads as the tiles landing and the rest of
                // the screen following a beat behind.
                if isOwned && !viewModel.recentActivities.isEmpty {
                    recentSection
                        .padding(.horizontal, 20)
                }

                // The market-cap value, monthly delta, chart, and range picker
                // all live inside this reused, self-contained section, which
                // manages its own insets.
                if !isUSDF {
                    CurrencyInfoMarketCapSection(
                        marketCap: viewModel.marketCap,
                        currencyCode: ratesController.balanceCurrency,
                        marketCapController: marketCapController,
                        isReady: !defersHeavyContent
                    )
                }

                CurrencyInfoAboutSection(
                    description: currencyDescription,
                    socialLinks: isUSDF ? [] : decodedMetadata.socialLinks
                )
                .padding(.horizontal, 20)

                if !isUSDF, let createdAt = metadata.createdAt {
                    Text("Created \(createdAt.formatted(date: .abbreviated, time: .omitted))".uppercased())
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                }
                }
                .opacity(contentOpacity)
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        // The card is the screen's subject and runs edge to edge; an indicator
        // riding over it is noise.
        .scrollIndicators(.hidden)
        // Content fades out under the toolbar instead of meeting the system's
        // hard scroll-edge line.
        .modifier(SoftTopScrollEdge())
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > Self.titleHandoffOffset
        } action: { _, scrolledPast in
            onScrolledPastTitle(scrolledPast)
        }
        // Reads where the drag began. A gesture on the card itself is not
        // delivered before the scroll view starts reporting overscroll, so the
        // flag was still false when the first pull arrived and every update was
        // rejected; asking the scroll view and comparing against the card's
        // frame gives an answer that is right from the first callback.
        // `.global` on purpose: the card's frame below is captured in the same
        // space. A drag reports in its own local space by default, which is
        // offset from global by wherever the scroll view sits — enough to move
        // the card's rectangle down onto the activity rows, so the dismissal
        // answered to a drag there instead of on the card.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { drag in
                    guard !hasJudgedOrigin else { return }
                    hasJudgedOrigin = true
                    touchBeganOnCard = heroFrame.contains(drag.startLocation)
                }
        )
        // Pull-to-close rides the scroll view's own overscroll rather than a
        // drag gesture of its own: a gesture layered over a scroll view has to
        // guess when it is competing with a scroll, whereas overscroll only
        // exists once the content is already at its top.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
        } action: { _, pulled in
            // Only a finger, and only one that started on the card. A flick
            // back up overshoots the top and bounces under its own momentum,
            // which is overscroll nobody asked for; and pulling the page down
            // from the tiles or the chart is a scroll, not a dismissal.
            guard isDragging, touchBeganOnCard else { return }
            didScrub = true
            pullDistance = pulled
            onPulledDown(pulled)
        }
        .onScrollPhaseChange { previous, phase in
            if phase == .interacting {
                isDragging = true
                return
            }

            // Judge the pull as the finger leaves the glass, and only then —
            // the later settle from deceleration to idle is not a second pull.
            guard previous == .interacting else { return }
            isDragging = false
            // Ended whenever this drag moved anything, rather than on the origin
            // flag — the screen has to be put back either way.
            if didScrub {
                onPullEnded(pullDistance)
            }
            touchBeganOnCard = false
            hasJudgedOrigin = false
            didScrub = false
            pullDistance = 0
        }
        // Started immediately rather than after the transition: the read itself
        // runs off the main thread, so it costs the animation nothing, and it
        // lands well before the page finishes fading in — which is what keeps
        // Recent from arriving as a second stage.
        .task {
            await viewModel.loadRecentActivities(limit: Self.recentPreviewCount)
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        TokenCardView(data: heroData, height: 224)
            // Destination of the wallet card's morph when hosted as an overlay,
            // so the tapped card becomes this one rather than cross-fading.
            .modifier(HeroCardMatch(mint: metadata.mint, namespace: cardNamespace))
    }

    private var heroData: TokenCardData {
        let appreciation = viewModel.appreciation
        // Never render "-$0.00": a sub-cent delta reads as positive.
        let positive = appreciation.isPositive || !appreciation.amount.hasDisplayableValue
        let appreciationText = (positive ? "+" : "-") + appreciation.amount.formatted()

        return TokenCardData(
            mint: metadata.mint,
            name: metadata.name,
            imageURL: metadata.imageURL,
            balanceText: isOwned ? viewModel.balance.formatted() : "",
            appreciationText: isOwned ? appreciationText : nil,
            colors: session.billColors(for: metadata.mint),
            isUSDF: isUSDF
        )
    }

    // MARK: - Actions

    /// An action-tile glyph: either an SF Symbol or a bundled template asset.
    private enum TileIcon {
        case system(String)
        case asset(String)
    }

    @ViewBuilder private var actionTiles: some View {
        HStack(spacing: 12) {
            if isOwned {
                // Convert works from any held currency — including Dollars,
                // which converts via a reserves buy.
                actionTile("Give", icon: .asset("IconBanknote"), action: onGive)
                actionTile("Convert", icon: .system("arrow.up.arrow.down"), action: onConvert)
                actionTile("Withdraw", icon: .system("arrow.up"), action: onWithdraw)
            } else {
                actionTile("Get", icon: .system("arrow.down"), action: onBuy)
            }
        }
    }

    private func actionTile(_ title: String, icon: TileIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                tileIcon(icon)
                    .frame(height: 28)
                Text(title)
                    .font(.appTextSmall)
            }
            .foregroundStyle(Color.textMain)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func tileIcon(_ icon: TileIcon) -> some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 22, weight: .regular))
        case .asset(let name):
            // Figma exports these glyphs at 28×28 (template-rendered, so they
            // tint with the tile's foreground).
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        RecentActivitySection(
            activities: viewModel.recentActivities,
            onShowAll: onShowTransactionHistory
        )
    }

    // MARK: - Copy

    private var currencyDescription: String {
        if isUSDF {
            return "Dollars are a 1:1 USD stablecoin managed by Coinbase."
        }
        return metadata.bio ?? "No information"
    }
}
