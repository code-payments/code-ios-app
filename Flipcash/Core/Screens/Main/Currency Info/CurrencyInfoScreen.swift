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

    @State private var isShowingTransactionHistory: Bool = false
    @State private var isShowingFundingSelection: Bool = false
    @State private var presentedBuyViewModel: CurrencyBuyViewModel?
    @State private var presentedSellViewModel: CurrencySellViewModel?
    @State private var isShowingCurrencySelection: Bool = false
    /// Drives the navigation push to `GiveScreen`. Separate from
    /// `giveViewModel.isPresented` (which triggers business logic only)
    /// so that `dismissParentContainer` can tear down the sheet without
    /// an intermediate pop animation.
    @State private var isShowingGive: Bool = false

    let session: Session

    private var mintMetadata: StoredMintMetadata? {
        viewModel.mintMetadata
    }

    private var isUSDF: Bool {
        mintMetadata?.mint == .usdf
    }

    private var currencyDescription: String {
        return mintMetadata?.bio ?? "No information"
    }

    @Environment(WalletConnection.self) private var walletConnection

    private let mint: PublicKey
    private let container: Container
    private let ratesController: RatesController
    private let sessionContainer: SessionContainer
    private let marketCapController: MarketCapController
    private let showFundingOnAppear: Bool

    // MARK: - Init -

    /// Creates the screen by mint address. Metadata is loaded from the database
    /// (fast path) or fetched from the network, showing a loading state until ready.
    init(mint: PublicKey, container: Container, sessionContainer: SessionContainer, showFundingOnAppear: Bool = false) {
        self.mint                = mint
        self.container           = container
        self.ratesController     = sessionContainer.ratesController
        self.session             = sessionContainer.session
        self.sessionContainer    = sessionContainer
        self.showFundingOnAppear = showFundingOnAppear

        self.viewModel = CurrencyInfoViewModel(
            mint: mint,
            session: sessionContainer.session,
            database: sessionContainer.database,
            ratesController: sessionContainer.ratesController
        )

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

    /// Creates the screen with pre-fetched metadata for instant display.
    /// The title and icon render immediately; a background refresh still runs
    /// via ``CurrencyInfoViewModel/loadMintMetadata()`` to pick up any updates.
    init(metadata: MintMetadata, container: Container, sessionContainer: SessionContainer) {
        self.mint                = metadata.address
        self.container           = container
        self.ratesController     = sessionContainer.ratesController
        self.session             = sessionContainer.session
        self.sessionContainer    = sessionContainer
        self.showFundingOnAppear = false

        self.viewModel = CurrencyInfoViewModel(
            metadata: metadata,
            session: sessionContainer.session,
            database: sessionContainer.database,
            ratesController: sessionContainer.ratesController
        )

        self.giveViewModel = GiveViewModel(
            container: container,
            sessionContainer: sessionContainer
        )

        self.marketCapController = MarketCapController(
            mint: metadata.address,
            ratesController: sessionContainer.ratesController,
            client: container.client
        )
    }

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            switch viewModel.loadingState {
            case .loading:
                CurrencyInfoLoadingView()
            case .loaded(let metadata):
                loadedContent(metadata: metadata)
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
                ToolbarItem(placement: .navigationBarTrailing) {
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
            await viewModel.loadMintMetadata()

            if showFundingOnAppear {
                isShowingFundingSelection = true
            }
        }
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

    @ViewBuilder private func loadedContent(metadata: StoredMintMetadata) -> some View {
        // Compute values once per body evaluation instead of on every property reference.
        let balance = viewModel.balance
        let appreciation = viewModel.appreciation
        let marketCap = viewModel.marketCap
        let reserveBalance = viewModel.reserveBalance

        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack {
                        Button {
                            isShowingCurrencySelection.toggle()
                        } label: {
                            AmountText(
                                flagStyle: balance.currencyCode.flagStyle,
                                content: balance.formatted(),
                                showChevron: true
                            )
                            .font(.appDisplayLarge)
                            .foregroundStyle(Color.textMain)
                        }
                        .frame(height: 60)
                        .frame(maxWidth: .infinity)

                        if !isUSDF && balance.quarks > 0 {
                            ValueAppreciation(amount: appreciation.amount, isPositive: appreciation.isPositive)
                                .padding(.top, 8)

                            Button("View Transaction") {
                                isShowingTransactionHistory.toggle()
                            }
                                .buttonStyle(.filled20)
                                .padding(.top, 40)
                        }
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 25)
                    .vSeparator(color: .rowSeparator)
                    .padding(.horizontal, 20)

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

                        // Social Links
                        if !isUSDF && !metadata.metadata.socialLinks.isEmpty {
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(metadata.metadata.socialLinks) { socialLink in
                                        switch socialLink {
                                        case .website(let url):
                                            Button("Website") {
                                                UIApplication.shared.open(url)
                                            }
                                            .buttonStyle(.icon(.globus))
                                        case .x(let handle):
                                            Button(handle) {
                                                UIApplication.shared.open(URL(string: "https://x.com/\(handle)")!)
                                            }
                                            .buttonStyle(.icon(.twitter))
                                        case .telegram(let username):
                                            Button("Telegram") {
                                                UIApplication.shared.open(URL(string: "https://t.me/\(username)")!)
                                            }
                                            .buttonStyle(.icon(.chat))
                                        case .discord(let inviteCode):
                                            Button("Discord") {
                                                UIApplication.shared.open(URL(string: "https://discord.gg/\(inviteCode)")!)
                                            }
                                            .buttonStyle(.icon(.chat))
                                        }
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            .padding(.horizontal, -20) // Extend past the parent's padding
                            .contentMargins(.horizontal, 20) // Inset the scroll content to match
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
                        isShowingFundingSelection = true
                    }
                        .buttonStyle(.filled)

                    if balance.quarks > 0 {
                        CodeButton(style: .filledSecondary, title: "Give") {
                            Analytics.buttonTapped(name: .give)
                            ratesController.selectToken(mint)
                            giveViewModel.isPresented = true
                            isShowingGive = true
                        }
                        
                        
                        CodeButton(style: .filledSecondary, title: "Sell") {
                            Analytics.buttonTapped(name: .sell)
                            presentedSellViewModel = CurrencySellViewModel(
                                currencyMetadata: metadata,
                                session: session,
                                ratesController: ratesController
                            )
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $isShowingTransactionHistory) {
            TransactionHistoryScreen(
                mintMetadata: metadata,
                container: container,
                sessionContainer: sessionContainer
            )
        }
        .navigationDestinationCompat(item: Bindable(walletConnection).processing) { processing in
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
        .sheet(isPresented: Bindable(walletConnection).isShowingAmountEntry) {
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
        .navigationDestination(isPresented: $isShowingGive) {
            GiveScreen(viewModel: giveViewModel)
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
            FundingSelectionSheet(
                reserveBalance: reserveBalance,
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
        .dialog(item: Bindable(walletConnection).dialogItem)
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
