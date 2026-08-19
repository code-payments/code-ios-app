//
//  CurrencyInfoScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-10-28.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

/// Thin environment-reading wrapper that hands the DI containers to
/// ``CurrencyInfoScreenContent``, whose two-init delegation builds the `@State`
/// view model and the market-cap controller synchronously from the mint.
/// `.id(mint)` on this wrapper at the call site rebuilds both when the mint
/// changes.
struct CurrencyInfoScreen: View {

    /// How the screen is hosted. The content, view model and behaviour are the
    /// same either way — only the top chrome differs, since an overlay is not a
    /// navigation destination and so cannot use `.toolbar`.
    enum Presentation {
        /// Pushed onto a navigation stack; the system supplies the back button.
        case pushed
        /// Layered over the wallet, holding the card the wallet was showing.
        /// Draws its own back button, which calls the closure.
        ///
        /// The host opens the screen by displacing the hero card down to where
        /// the wallet's deck was holding it and animating `heroOffset` back to
        /// zero, while `contentOpacity` brings the rest of the screen in behind
        /// it. The card is the screen's own from the first frame — it is never a
        /// copy laid over the top — so it scrolls with the content immediately
        /// and there is no hand-over to mistime.
        /// `onPull` reports a pull-to-close in progress, 0 to 1, so the host can
        /// run its opening transition backwards under the finger; `onPullEnded`
        /// says whether the finger lifted past the point of no return.
        case overlay(
            onClose: () -> Void,
            heroOffset: CGFloat = 0,
            contentOpacity: Double = 1,
            onPull: (CGFloat) -> Void = { _ in },
            onPullEnded: (Bool, CGFloat) -> Void = { _, _ in }
        )
        /// Laid out inline beneath the card the wallet keeps on screen, so it
        /// draws neither the hero card nor any top chrome.
        case inline
    }

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    let mint: PublicKey
    var showBuyOnAppear: Bool = false
    var presentation: Presentation = .pushed
    /// Held true by a host that is animating this screen in.
    var defersHeavyContent: Bool = false

    var body: some View {
        CurrencyInfoScreenContent(
            mint: mint,
            container: container,
            sessionContainer: sessionContainer,
            showBuyOnAppear: showBuyOnAppear,
            presentation: presentation,
            defersHeavyContent: defersHeavyContent
        )
    }
}

private struct CurrencyInfoScreenContent: View {
    @State private var viewModel: CurrencyInfoViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    /// Set by the wallet so this screen zooms out of the tapped token card.
    @Environment(\.walletCardNamespace) private var cardNamespace

    @State private var presentedSellViewModel: CurrencySellViewModel?
    @State private var isShowingCurrencySelection: Bool = false
    /// New UI: the toolbar title only appears once the hero card's own title has
    /// scrolled out of view (Apple Wallet / App Store behaviour).
    @State private var showsToolbarTitle: Bool = false
    /// How far through a pull-to-close the content currently is, 0 to 1. Used to
    /// fade the chrome so the gesture is legible before it commits.
    @State private var pullProgress: CGFloat = 0

    let session: Session

    private var mintMetadata: StoredMintMetadata? {
        viewModel.mintMetadata
    }

    /// Derived from the mint the screen was pushed with, not the async
    /// metadata load — the navigation-bar item set must not change when
    /// metadata lands mid-transition (iOS 27 wedges in nav-bar autolayout
    /// when toolbar items churn during a push).
    private var isUSDF: Bool {
        mint == .usdf
    }

    private let mint: PublicKey
    private let ratesController: RatesController
    private let marketCapController: MarketCapController
    private let showBuyOnAppear: Bool
    private let presentation: CurrencyInfoScreen.Presentation
    private let defersHeavyContent: Bool

    private var isNewUI: Bool { BetaFlags.shared.hasEnabled(.newUI) }

    /// Overlay hosting draws its own chrome; pushed hosting uses `.toolbar`.
    private var overlayClose: (() -> Void)? {
        if case .overlay(let onClose, _, _, _, _) = presentation { return onClose }
        return nil
    }

    /// How far the hero card is displaced from its resting slot while the host
    /// animates it in.
    private var heroOffset: CGFloat {
        if case .overlay(_, let offset, _, _, _) = presentation { return offset }
        return 0
    }

    /// Everything except the hero card, which the host brings in behind it.
    private var contentOpacity: Double {
        if case .overlay(_, _, let opacity, _, _) = presentation { return opacity }
        return 1
    }

    /// Reports a pull-to-close to the host, which owns the transition it undoes.
    private var onPull: (CGFloat) -> Void {
        if case .overlay(_, _, _, let onPull, _) = presentation { return onPull }
        return { _ in }
    }

    private var onPullEnded: (Bool, CGFloat) -> Void {
        if case .overlay(_, _, _, _, let onEnded) = presentation { return onEnded }
        return { _, _ in }
    }

    /// The wallet keeps its own card above an inline-hosted screen.
    private var showsHeroCard: Bool {
        if case .inline = presentation { return false }
        return true
    }

    /// The wallet already shows the card above an inline-hosted screen.
    private var isInline: Bool {
        if case .inline = presentation { return true }
        return false
    }

    /// Only a pushed screen has a navigation bar to put items in.
    private var usesToolbar: Bool {
        if case .pushed = presentation { return true }
        return false
    }

    // MARK: - Init -

    private init(
        mint: PublicKey,
        viewModel: CurrencyInfoViewModel,
        container: Container,
        sessionContainer: SessionContainer,
        showBuyOnAppear: Bool,
        presentation: CurrencyInfoScreen.Presentation,
        defersHeavyContent: Bool
    ) {
        self.presentation        = presentation
        self.defersHeavyContent  = defersHeavyContent
        self.mint                = mint
        self.ratesController     = sessionContainer.ratesController
        self.session             = sessionContainer.session
        self.showBuyOnAppear = showBuyOnAppear
        self.viewModel           = viewModel

        self.marketCapController = MarketCapController(
            mint: mint,
            ratesController: sessionContainer.ratesController,
            client: container.client
        )
    }

    /// Creates the screen by mint address. Metadata is loaded from the database
    /// (fast path) or fetched from the network, showing a loading state until ready.
    init(
        mint: PublicKey,
        container: Container,
        sessionContainer: SessionContainer,
        showBuyOnAppear: Bool = false,
        presentation: CurrencyInfoScreen.Presentation = .pushed,
        defersHeavyContent: Bool = false
    ) {
        self.init(
            mint: mint,
            viewModel: CurrencyInfoViewModel(
                mint: mint,
                session: sessionContainer.session,
                database: sessionContainer.database,
                ratesController: sessionContainer.ratesController
            ),
            container: container,
            sessionContainer: sessionContainer,
            showBuyOnAppear: showBuyOnAppear,
            presentation: presentation,
            defersHeavyContent: defersHeavyContent
        )
    }

    // MARK: - Body -

    var body: some View {
        // Fades with the rest of the screen when hosted as an overlay. Held
        // opaque instead, it covers the wallet the instant the screen is built,
        // so the deck never visibly clears and the content simply materialises
        // over black while the card is still travelling. The host fades the
        // wallet out first, so this comes up over an already-dark screen rather
        // than cross-fading with a visible one.
        Background(color: overlayClose == nil ? .backgroundMain : .backgroundMain.opacity(contentOpacity)) {
            switch viewModel.loadingState {
            case .loading:
                CurrencyInfoLoadingView()
            case .loaded(let metadata, let decodedMetadata):
                if isNewUI {
                    CurrencyInfoContentV2(
                        metadata: metadata,
                        decodedMetadata: decodedMetadata,
                        viewModel: viewModel,
                        ratesController: ratesController,
                        marketCapController: marketCapController,
                        session: session,
                        onGive: {
                            Analytics.buttonTapped(name: .give)
                            router.push(.give(mint))
                        },
                        // New UI pushes the convert flow onto the current stack —
                        // sells this currency into a chosen destination.
                        onConvert: { router.push(.convertCurrency(mint)) },
                        // New UI pushes the buy flow onto the current stack rather
                        // than presenting it as a sheet.
                        onBuy: { router.push(.buyCurrency(mint)) },
                        onWithdraw: { router.push(.withdrawCurrency(mint)) },
                        onShowTransactionHistory: { router.push(.transactionHistory(metadata.mint)) },
                        onScrolledPastTitle: { scrolledPast in
                            guard showsToolbarTitle != scrolledPast else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsToolbarTitle = scrolledPast
                            }
                        },
                        onPulledDown: { pulled in
                            guard overlayClose != nil else { return }
                            let progress = min(1, pulled / Self.pullToCloseDistance)
                            pullProgress = progress
                            onPull(progress)
                        },
                        onPullEnded: { pulled in
                            guard overlayClose != nil else { return }
                            let passed = pulled >= Self.pullToCloseDistance
                            if !passed {
                                withAnimation(.smooth(duration: 0.25)) { pullProgress = 0 }
                            }
                            onPullEnded(passed, pulled)
                        },
                        showsHeroCard: showsHeroCard,
                        heroOffset: heroOffset,
                        contentOpacity: contentOpacity,
                        defersHeavyContent: defersHeavyContent
                    )
                } else {
                    LoadedContent(
                    metadata: metadata,
                    decodedMetadata: decodedMetadata,
                    viewModel: viewModel,
                    ratesController: ratesController,
                    marketCapController: marketCapController,
                    onShowTransactionHistory: { router.push(.transactionHistory(metadata.mint)) },
                    onShowCurrencySelection: { isShowingCurrencySelection = true },
                    onBuy: { router.presentNested(.buy(mint)) },
                    onGive: {
                        Analytics.buttonTapped(name: .give)
                        router.push(.give(mint))
                    },
                    onSell: {
                        Analytics.buttonTapped(name: .sell)
                        presentedSellViewModel = CurrencySellViewModel(
                            currencyMetadata: metadata,
                            session: session,
                            ratesController: ratesController
                        )
                    },
                    onDeposit: { router.push(.usdcDepositEducation) },
                    onWithdraw: { router.push(.withdrawCurrency(mint)) }
                    )
                }
            case .error(let error):
                CurrencyInfoErrorView(error: error) {
                    dismiss()
                }
            }
        }
        // Overlay hosting is not a navigation destination, so the chrome the
        // toolbar would provide is drawn over the content instead — and the
        // content needs the same top inset a nav bar would have reserved.
        .modifier(OverlayTopInset(active: overlayClose != nil, opacity: contentOpacity))
        .overlay(alignment: .top) {
            if overlayClose != nil {
                overlayChrome
                    .frame(height: Self.overlayBarHeight)
                    // Arrives with the rest of the screen; only the card itself
                    // is held at full strength through the opening. Fades again
                    // as a pull-to-close builds, so the gesture is legible
                    // before it commits.
                    .opacity(contentOpacity * (1 - pullProgress))
            }
        }
        .toolbar(usesToolbar ? .automatic : .hidden, for: .navigationBar)
        .toolbarTitleDisplayMode(.inline)
        // The bar background is deliberately left in place: it renders the
        // scroll edge effect, and hiding it removes the soft fade the content
        // scrolls under (see CurrencyInfoContentV2's scrollEdgeEffectStyle).
        .toolbar {
            // Kept mounted and faded rather than inserted/removed — churning
            // toolbar items mid-transition wedges nav-bar layout. In the new UI
            // the item draws its own capsule, so the system platter stays off.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: isNewUI ? .topBarLeading : .principal) {
                    toolbarContent()
                        .opacity(isNewUI && !showsToolbarTitle ? 0 : 1)
                }
                .sharedBackgroundVisibility(isNewUI ? .hidden : .automatic)
            } else {
                ToolbarItem(placement: isNewUI ? .topBarLeading : .principal) {
                    toolbarContent()
                        .opacity(isNewUI && !showsToolbarTitle ? 0 : 1)
                }
            }
            if !isUSDF {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: URL(string: "https://app.flipcash.com/token/\(mint.base58)")!) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        Analytics.buttonTapped(name: .shareTokenInfo)
                    })
                }
            }
        }
        .task {
            ratesController.ensureMintSubscribed(mint)
            await viewModel.loadMintMetadata()

            if showBuyOnAppear {
                router.presentNested(.buy(mint))
            }
        }
        .sheet(item: $presentedSellViewModel) { sellViewModel in
            CurrencySellAmountScreen(viewModel: sellViewModel)
        }
        .sheet(isPresented: $isShowingCurrencySelection) {
            CurrencySelectionScreen(ratesController: ratesController)
        }
        // Dialogs originating in the buy flow route through
        // `session.dialogItem` so they surface in `DialogWindow` rather than
        // fighting the sheet stack here. Binding `.dialog(item:)` on this
        // screen would mount a sheet that competes with the `.buy` sheet's
        // presentation queue.
    }

    /// Height of the chrome an overlay draws in place of the navigation bar.
    fileprivate static let overlayBarHeight: CGFloat = 44

    /// How far the content has to be pulled past its top to count as a close —
    /// far enough that an overscroll bounce at the end of a flick cannot reach
    /// it by accident.
    private static let pullToCloseDistance: CGFloat = 110

    /// Top inset for overlay hosting. The wallet parks the opened card at
    /// `WalletCardGeometry.openCardTopInset`; the content adds 8pt of its own
    /// padding above the hero card, so this makes the two line up exactly and
    /// the hand-off invisible.
    ///
    /// The further 6pt is the scroll view's own soft top edge, which insets the
    /// first row by that much. Without it the hero card lands 6pt below where
    /// the wallet parked the card, and the hand-off reads as the card
    /// overshooting and settling back.
    fileprivate static let overlayContentInset: CGFloat = WalletCardGeometry.openCardTopInset - 8 - 6

    /// Close + title pill + share. Used only when hosted as an overlay.
    ///
    /// A close box rather than a back chevron: the screen is lifted over the
    /// wallet rather than pushed onto it, and it does not offer the edge-swipe
    /// that a chevron would imply.
    @ViewBuilder private var overlayChrome: some View {
        HStack(spacing: 8) {
            Button {
                overlayClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.textMain)
                    .frame(width: Self.overlayBarHeight, height: Self.overlayBarHeight)
                    // Hit-test the whole target, not just the glyph.
                    .contentShape(Circle())
                    .modifier(CircleGlass())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("currency-info-back")

            toolbarContent()
                .opacity(showsToolbarTitle ? 1 : 0)

            Spacer(minLength: 0)

            if !isUSDF {
                ShareLink(item: URL(string: "https://app.flipcash.com/token/\(mint.base58)")!) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.textMain)
                        .frame(width: Self.overlayBarHeight, height: Self.overlayBarHeight)
                        .contentShape(Circle())
                        .modifier(CircleGlass())
                }
                .simultaneousGesture(TapGesture().onEnded {
                    Analytics.buttonTapped(name: .shareTokenInfo)
                })
            }
        }
        .padding(.horizontal, 16)
        .animation(.smooth(duration: 0.2), value: showsToolbarTitle)
    }

    @ViewBuilder private func toolbarContent() -> some View {
        // USDF's name is already "Dollars", so no special-case is needed.
        if let metadata = mintMetadata {
            if isNewUI {
                if #available(iOS 26.0, *) {
                    // Compact leading label — the system supplies the Liquid Glass
                    // platter around it on iOS 26. `.fixedSize()` is required: the
                    // toolbar compresses the item to its icon otherwise, dropping
                    // the text. `CurrencyLabel` is row-shaped (it spaces name and
                    // amount apart with a Spacer), so it can't be reused here.
                    HStack(spacing: 8) {
                        RemoteImage(url: metadata.imageURL)
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            // Semantic styles rather than fixed white/grey: inside
                            // the glass they pick up the system's vibrancy, so the
                            // label stays legible over a bright bill card beneath.
                            Text(metadata.name)
                                .font(.appTextSmall)
                                .foregroundStyle(.primary)
                            // USDF has no market cap (no bonding curve), so it
                            // stays a single-line pill.
                            if !isUSDF {
                                Text(viewModel.marketCap.formatted())
                                    .font(.appTextCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    // The capsule is drawn here rather than by the toolbar: the
                    // system platter sizes itself to the content with a fixed inset
                    // and swallows most of the trailing padding the spec calls for.
                    .padding(.leading, 8)
                    .padding(.trailing, 20)
                    // Sized to the chrome height rather than left to hug its two
                    // lines of text, which left the capsule a few points shorter
                    // than the round buttons either side of it.
                    .frame(height: Self.overlayBarHeight)
                    .modifier(CapsuleGlass())
                } else {
                    // iOS 18 has no Liquid Glass; a materialized capsule reads as
                    // heavy chrome, so the scroll-revealed title is just the plain
                    // token name.
                    Text(metadata.name)
                        .font(.appTextMedium)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                }
            } else {
                CurrencyLabel(
                    imageURL: metadata.imageURL,
                    name: metadata.name,
                    amount: nil
                )
            }
        }
    }
}

/// Reserves the space a navigation bar would have taken, so overlay-hosted
/// content starts below the chrome instead of underneath it, and fades what
/// scrolls up into that space.
///
/// The system's own soft scroll edge is drawn by the navigation bar's
/// background, and an overlay has no navigation bar — it draws its own chrome
/// over the content — so without this the page scrolls up to meet the status
/// bar at full strength.
private struct OverlayTopInset: ViewModifier {
    let active: Bool
    /// Matches the rest of the screen's arrival, so the fade does not darken the
    /// card before the screen behind it exists.
    var opacity: Double = 1

    /// The screen's own top inset, read before this modifier adds its own, so
    /// the fade can be positioned against the status bar rather than a fixed
    /// guess at its height.
    @State private var statusBarHeight: CGFloat = 0

    /// How far below the status bar the content returns to full strength —
    /// the height of the chrome, so it is clear again just under the buttons.
    private static let fadeLength = CurrencyInfoScreenContent.overlayBarHeight

    func body(content: Content) -> some View {
        if active {
            content
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: {
                    statusBarHeight = $0
                }
                .safeAreaInset(edge: .top) {
                    Color.clear.frame(height: CurrencyInfoScreenContent.overlayContentInset)
                }
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.backgroundMain, Color.backgroundMain.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: statusBarHeight + Self.fadeLength)
                    .ignoresSafeArea(edges: .top)
                    .opacity(opacity)
                    .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}

/// Circular Liquid Glass for the overlay's back and share buttons, matching the
/// platters the toolbar gives those items when the screen is pushed.
private struct CircleGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// The title pill's Liquid Glass capsule. Drawn by the label itself so its
/// padding is honoured — the toolbar's own platter hugs the content and clips
/// most of the trailing inset away.
private struct CapsuleGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - Loaded Content -

/// Extracted subview that isolates observation tracking from the parent.
/// Reads from `viewModel`, `ratesController`, and `session` (indirectly)
/// are scoped to this view's body — the parent body is not invalidated
/// when poll-driven rate/balance changes occur every ~10 seconds.
private struct LoadedContent: View {
    let metadata: StoredMintMetadata
    /// Pre-decoded `MintMetadata` from the view model. Passed in ready-made
    /// so the body doesn't JSON-decode on every observation-churn re-eval.
    let decodedMetadata: MintMetadata
    let viewModel: CurrencyInfoViewModel
    let ratesController: RatesController
    let marketCapController: MarketCapController

    let onShowTransactionHistory: () -> Void
    let onShowCurrencySelection: () -> Void
    let onBuy: () -> Void
    let onGive: () -> Void
    let onSell: () -> Void
    let onDeposit: () -> Void
    let onWithdraw: () -> Void

    private var isUSDF: Bool {
        metadata.mint == .usdf
    }

    private var currencyDescription: String {
        metadata.bio ?? "No information"
    }

    var body: some View {
        let balance = viewModel.balance
        let appreciation = viewModel.appreciation
        let marketCap = viewModel.marketCap

        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    CurrencyInfoHeaderSection(
                        balance: balance,
                        appreciation: appreciation,
                        isUSDF: isUSDF,
                        onCurrencySelection: onShowCurrencySelection,
                        onViewTransaction: onShowTransactionHistory
                    )

                    // Currency Info
                    section(spacing: 20) {
                        if !isUSDF {
                            HStack {
                                Image(systemName: "text.justify.left")
                                    .padding(.bottom, -1)
                                Text("Currency Info")
                            }
                            .font(.appBarButton)
                            .foregroundStyle(Color.textMain)

                            if let createdAt = metadata.createdAt {
                                Text("Created \(createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .foregroundStyle(Color.textSecondary)
                                    .font(.appTextSmall)
                            }
                        }

                        ExpandableText(currencyDescription)
                            .foregroundStyle(Color.textSecondary)
                            .font(.appTextSmall)

                        if !isUSDF && !decodedMetadata.socialLinks.isEmpty {
                            CurrencyInfoSocialLinksSection(socialLinks: decodedMetadata.socialLinks)
                        }
                    }

                    // Market Cap
                    if !isUSDF {
                        CurrencyInfoMarketCapSection(
                            marketCap: marketCap,
                            currencyCode: ratesController.balanceCurrency,
                            marketCapController: marketCapController
                        )
                    }

                    // Reserve space so the floating footer doesn't overlap
                    // scrolled content.
                    Color
                        .clear
                        .padding(.bottom, 100)
                }
            }

            // Floating Footer
            if isUSDF {
                CurrencyInfoFooter {
                    Button("Deposit") {
                        onDeposit()
                    }
                    .buttonStyle(.filled)

                    CodeButton(style: .filledSecondary, title: "Withdraw") {
                        onWithdraw()
                    }
                }
            } else {
                CurrencyInfoFooter {
                    Button("Buy") {
                        onBuy()
                    }
                    .buttonStyle(.filled)

                    if balance.hasDisplayableValue {
                        CodeButton(style: .filledSecondary, title: "Give") {
                            onGive()
                        }

                        CodeButton(style: .filledSecondary, title: "Sell") {
                            onSell()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func section(spacing: CGFloat = 0, @ViewBuilder builder: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            builder()
        }
        .padding(.top, 20)
        .padding(.bottom, 25)
        .vSeparator(color: .rowSeparator)
        .padding(.horizontal, 20)
    }
}
