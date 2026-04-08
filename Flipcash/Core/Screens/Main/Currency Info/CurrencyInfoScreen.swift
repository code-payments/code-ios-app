//
//  CurrencyInfoScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-10-28.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct CurrencyInfoScreen: View {
    @State private var viewModel: CurrencyInfoViewModel
    @State private var giveViewModel: GiveViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var transactionHistoryMetadata: StoredMintMetadata?
    @State private var isShowingFundingSelection: Bool = false
    @State private var presentedBuyViewModel: CurrencyBuyViewModel?
    @State private var presentedSellViewModel: CurrencySellViewModel?
    @State private var isShowingCurrencySelection: Bool = false
    /// Drives the navigation push to `GiveScreen`. Separate from
    /// `giveViewModel.isPresented` (which triggers business logic only)
    /// so that `dismissParentContainer` can tear down the sheet without
    /// an intermediate pop animation.
    @State private var isShowingGive: Bool = false
    /// Non-nil while the Onramp sheet is presented. Setting it presents the
    /// sheet with a fresh `OnrampViewModel`; nil'ing it dismisses.
    @State private var onrampDestination: OnrampViewModel.BuyDestination?

    let session: Session

    private var mintMetadata: StoredMintMetadata? {
        viewModel.mintMetadata
    }

    private var isUSDF: Bool {
        mintMetadata?.mint == .usdf
    }

    @Environment(WalletConnection.self) private var walletConnection

    private let mint: PublicKey
    private let container: Container
    private let ratesController: RatesController
    private let sessionContainer: SessionContainer
    private let marketCapController: MarketCapController
    private let showFundingOnAppear: Bool

    // MARK: - Init -

    private init(
        mint: PublicKey,
        viewModel: CurrencyInfoViewModel,
        container: Container,
        sessionContainer: SessionContainer,
        showFundingOnAppear: Bool
    ) {
        self.mint                = mint
        self.container           = container
        self.ratesController     = sessionContainer.ratesController
        self.session             = sessionContainer.session
        self.sessionContainer    = sessionContainer
        self.showFundingOnAppear = showFundingOnAppear
        self.viewModel           = viewModel

        self.giveViewModel = GiveViewModel(
            container: container,
            sessionContainer: sessionContainer
        )

        self.marketCapController = MarketCapController(
            mint: mint,
            ratesController: sessionContainer.ratesController,
            client: container.client
        )
    }

    /// Creates the screen by mint address. Metadata is loaded from the database
    /// (fast path) or fetched from the network, showing a loading state until ready.
    init(mint: PublicKey, container: Container, sessionContainer: SessionContainer, showFundingOnAppear: Bool = false) {
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
            showFundingOnAppear: showFundingOnAppear
        )
    }

    /// Creates the screen with pre-fetched metadata for instant display.
    /// The title and icon render immediately; a background refresh still runs
    /// via ``CurrencyInfoViewModel/loadMintMetadata()`` to pick up any updates.
    init(metadata: MintMetadata, container: Container, sessionContainer: SessionContainer) {
        self.init(
            mint: metadata.address,
            viewModel: CurrencyInfoViewModel(
                metadata: metadata,
                session: sessionContainer.session,
                database: sessionContainer.database,
                ratesController: sessionContainer.ratesController
            ),
            container: container,
            sessionContainer: sessionContainer,
            showFundingOnAppear: false
        )
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            switch viewModel.loadingState {
            case .loading:
                CurrencyInfoLoadingView()
            case .loaded(let metadata):
                LoadedContent(
                    metadata: metadata,
                    viewModel: viewModel,
                    ratesController: ratesController,
                    marketCapController: marketCapController,
                    onShowTransactionHistory: { transactionHistoryMetadata = metadata },
                    onShowCurrencySelection: { isShowingCurrencySelection = true },
                    onBuy: { isShowingFundingSelection = true },
                    onGive: {
                        Analytics.buttonTapped(name: .give)
                        ratesController.selectToken(mint)
                        giveViewModel.isPresented = true
                        isShowingGive = true
                    },
                    onSell: {
                        Analytics.buttonTapped(name: .sell)
                        presentedSellViewModel = CurrencySellViewModel(
                            currencyMetadata: metadata,
                            session: session,
                            ratesController: ratesController
                        )
                    }
                )
            case .error(let error):
                CurrencyInfoErrorView(error: error) {
                    dismiss()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarContent()
            }
            if !isUSDF {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Analytics.buttonTapped(name: .shareTokenInfo)
                        let url = URL(string: "https://app.flipcash.com/token/\(mint.base58)")!
                        ShareSheet.present(url: url)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            ratesController.ensureMintSubscribed(mint)
            await viewModel.loadMintMetadata()

            if showFundingOnAppear {
                isShowingFundingSelection = true
            }
        }
        .navigationDestinationCompat(item: $transactionHistoryMetadata) { metadata in
            TransactionHistoryScreen(
                mintMetadata: metadata,
                database: sessionContainer.database
            )
        }
        .fullScreenCover(item: Bindable(walletConnection).processing) { processing in
            NavigationStack {
                SwapProcessingScreen(
                    swapId: processing.swapId,
                    swapType: .buyWithPhantom,
                    currencyName: processing.currencyName,
                    amount: processing.amount
                )
                .environment(\.dismissParentContainer, {
                    walletConnection.dismissProcessing()
                })
            }
        }
        .navigationDestination(isPresented: $isShowingGive) {
            GiveScreen(viewModel: giveViewModel)
        }
        .sheet(isPresented: Bindable(walletConnection).isShowingAmountEntry) {
            if let metadata = viewModel.mintMetadata {
                NavigationStack {
                    EnterWalletAmountScreen { quarks in
                        try await walletConnection.requestSwap(
                            usdc: quarks,
                            token: metadata.metadata
                        )
                    }
                    .toolbar {
                        ToolbarCloseButton {
                            walletConnection.isShowingAmountEntry = false
                        }
                    }
                }
            }
        }
        .dialog(item: $giveViewModel.dialogItem)
        .sheet(item: $presentedBuyViewModel) { buyViewModel in
            CurrencyBuyAmountScreen(viewModel: buyViewModel)
        }
        .sheet(item: $presentedSellViewModel) { sellViewModel in
            CurrencySellAmountScreen(viewModel: sellViewModel)
        }
        .sheet(isPresented: $isShowingCurrencySelection) {
            CurrencySelectionScreen(
                isPresented: $isShowingCurrencySelection,
                kind: .balance,
                ratesController: ratesController
            )
        }
        .sheet(isPresented: $isShowingFundingSelection) {
            if let metadata = viewModel.mintMetadata {
                FundingSelectionSheet(
                    reserveBalance: viewModel.reserveBalance,
                    isCoinbaseAvailable: session.hasCoinbaseOnramp,
                    onSelectReserves: {
                        Analytics.buttonTapped(name: .buyWithReserves)
                        presentedBuyViewModel = CurrencyBuyViewModel(
                            currencyPublicKey: metadata.mint,
                            currencyName: metadata.name,
                            session: session,
                            ratesController: ratesController
                        )
                        isShowingFundingSelection = false
                    },
                    onSelectCoinbase: {
                        Analytics.buttonTapped(name: .buyWithCoinbase)
                        onrampDestination = .init(
                            mint: metadata.mint,
                            name: metadata.name
                        )
                        isShowingFundingSelection = false
                    },
                    onSelectPhantom: {
                        Analytics.buttonTapped(name: .buyWithPhantom)
                        walletConnection.connectToPhantom()
                        isShowingFundingSelection = false
                    },
                    onDismiss: {
                        isShowingFundingSelection = false
                    }
                )
            }
        }
        .sheet(item: $onrampDestination) { destination in
            OnrampAmountScreen(
                destination: destination,
                session: sessionContainer.session,
                ratesController: sessionContainer.ratesController,
                flipClient: sessionContainer.flipClient,
                deeplinkInbox: sessionContainer.onrampDeeplinkInbox,
                pendingEmailVerification: sessionContainer.onrampDeeplinkInbox.take(),
                onDismiss: { onrampDestination = nil }
            )
        }
        .dialog(item: Bindable(walletConnection).dialogItem)
    }

    @ViewBuilder private func toolbarContent() -> some View {
        if let metadata = mintMetadata {
            if metadata.mint == .usdf {
                Text("USDF")
                    .font(.appBarButton)
                    .foregroundStyle(Color.textMain)
            } else {
                CurrencyLabel(
                    imageURL: metadata.imageURL,
                    name: metadata.name,
                    amount: nil
                )
            }
        } else {
            EmptyView()
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
    let viewModel: CurrencyInfoViewModel
    let ratesController: RatesController
    let marketCapController: MarketCapController

    let onShowTransactionHistory: () -> Void
    let onShowCurrencySelection: () -> Void
    let onBuy: () -> Void
    let onGive: () -> Void
    let onSell: () -> Void

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

                        Text(currencyDescription)
                            .foregroundStyle(Color.textSecondary)
                            .font(.appTextSmall)

                        if !isUSDF && !metadata.metadata.socialLinks.isEmpty {
                            CurrencyInfoSocialLinksSection(socialLinks: metadata.metadata.socialLinks)
                        }
                    }

                    // Market Cap
                    if !isUSDF {
                        CurrencyInfoMarketCapSection(
                            marketCap: marketCap,
                            currencyCode: ratesController.balanceCurrency,
                            marketCapController: marketCapController
                        )

                        Color
                            .clear
                            .padding(.bottom, 100)
                    }
                }
            }

            // Floating Footer
            if !isUSDF {
                CurrencyInfoFooter {
                    Button("Buy") {
                        onBuy()
                    }
                    .buttonStyle(.filled)

                    if balance.quarks > 0 {
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
