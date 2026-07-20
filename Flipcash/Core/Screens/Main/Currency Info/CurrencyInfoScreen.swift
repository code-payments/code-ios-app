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

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    let mint: PublicKey
    var showBuyOnAppear: Bool = false

    var body: some View {
        CurrencyInfoScreenContent(
            mint: mint,
            container: container,
            sessionContainer: sessionContainer,
            showBuyOnAppear: showBuyOnAppear
        )
    }
}

private struct CurrencyInfoScreenContent: View {
    @State private var viewModel: CurrencyInfoViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var presentedSellViewModel: CurrencySellViewModel?
    @State private var isShowingCurrencySelection: Bool = false

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

    // MARK: - Init -

    private init(
        mint: PublicKey,
        viewModel: CurrencyInfoViewModel,
        container: Container,
        sessionContainer: SessionContainer,
        showBuyOnAppear: Bool
    ) {
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
    init(mint: PublicKey, container: Container, sessionContainer: SessionContainer, showBuyOnAppear: Bool = false) {
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
            showBuyOnAppear: showBuyOnAppear
        )
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            switch viewModel.loadingState {
            case .loading:
                CurrencyInfoLoadingView()
            case .loaded(let metadata, let decodedMetadata):
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
            case .error(let error):
                CurrencyInfoErrorView(error: error) {
                    dismiss()
                }
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarContent()
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

    @ViewBuilder private func toolbarContent() -> some View {
        if isUSDF {
            Text("USDF")
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)
        } else if let metadata = mintMetadata {
            CurrencyLabel(
                imageURL: metadata.imageURL,
                name: metadata.name,
                amount: nil
            )
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
