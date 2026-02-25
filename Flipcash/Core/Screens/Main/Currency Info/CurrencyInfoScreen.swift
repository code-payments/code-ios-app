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
    @StateObject private var viewModel: CurrencyInfoViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var isShowingTransactionHistory: Bool = false
    @State private var isShowingFundingSelection: Bool = false
    @State private var isShowingBuyAmountEntry: Bool = false
    @State private var isShowingSellAmountEntry: Bool = false
    @State private var isShowingCurrencySelection: Bool = false

    @ObservedObject private var session: Session
    @StateObject private var currencyBuyViewModel: CurrencyBuyViewModel
    @State private var currencySellViewModel: CurrencySellViewModel?

    private var mintMetadata: StoredMintMetadata? {
        viewModel.mintMetadata
    }

    private var isUSDF: Bool {
        mintMetadata?.mint == .usdf
    }

    private var currencyDescription: String {
        return mintMetadata?.bio ?? "No information"
    }

    private var balance: Quarks {
        let rate = ratesController.rateForBalanceCurrency()
        let zeroQuarks: UInt64 = 0
        let zero = Quarks(quarks: zeroQuarks, currencyCode: rate.currency, decimals: PublicKey.usdf.mintDecimals)

        guard let mintMetadata else { return zero }
        guard let stored = session.balance(for: mintMetadata.mint) else { return zero }

        let exchanged = try? ExchangedFiat(underlying: stored.usdf, rate: rate, mint: .usdf)
        return exchanged?.converted ?? zero
    }

    private var reserveBalance: ExchangedFiat? {
        guard let stored = session.balance(for: .usdf) else { return nil }

        let rate = ratesController.rateForBalanceCurrency()
        return try? ExchangedFiat(underlying: stored.usdf, rate: rate, mint: .usdf)
    }

    private var appreciation: (amount: Quarks, isPositive: Bool) {
        let zeroQuarks: UInt64 = 0
        let zero = Quarks(quarks: zeroQuarks, currencyCode: ratesController.rateForBalanceCurrency().currency, decimals: PublicKey.usdf.mintDecimals)

        guard let mintMetadata, let balance = session.balance(for: mintMetadata.mint) else {
            return (zero, true)
        }
        let (appreciationValue, isPositive) = balance.computeAppreciation(with: ratesController.rateForBalanceCurrency())
        return (appreciationValue.converted, isPositive)
    }

    @Environment(WalletConnection.self) private var walletConnection

    private let mint: PublicKey
    private let container: Container
    private let ratesController: RatesController
    private let sessionContainer: SessionContainer
    private let marketCapController: MarketCapController
    private let showFundingOnAppear: Bool

    private var marketCap: Quarks {
        guard let mintMetadata else { return 0 }

        var supply: Int = 0
        if let supplyFromBonding = mintMetadata.supplyFromBonding {
            supply = Int(supplyFromBonding)
        }

        let curve = DiscreteBondingCurve()
        guard let mCap = curve.marketCap(for: supply) else {
            return 0
        }

        let usdc = try! Quarks(
            fiatDecimal: mCap,
            currencyCode: .usd,
            decimals: mintMetadata.mint.mintDecimals
        )

        let exchanged = try! ExchangedFiat(
            underlying: usdc,
            rate: ratesController.rateForBalanceCurrency(),
            mint: .usdf
        )

        return exchanged.converted
    }

    // MARK: - Init -

    init(mint: PublicKey, container: Container, sessionContainer: SessionContainer, showFundingOnAppear: Bool = false) {
        self.mint                = mint
        self.container           = container
        self.ratesController     = sessionContainer.ratesController
        self.session             = sessionContainer.session
        self.sessionContainer    = sessionContainer
        self.showFundingOnAppear = showFundingOnAppear

        _viewModel = .init(wrappedValue: CurrencyInfoViewModel(
            mint: mint,
            sessionContainer: sessionContainer
        ))

        _currencyBuyViewModel = .init(
            wrappedValue: CurrencyBuyViewModel(
                currencyPublicKey: mint,
                container: container,
                sessionContainer: sessionContainer
            )
        )

        self.marketCapController = MarketCapController(
            mint: mint,
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

            if let metadata = viewModel.mintMetadata, currencySellViewModel == nil {
                currencySellViewModel = CurrencySellViewModel(
                    currencyMetadata: metadata,
                    container: container,
                    sessionContainer: sessionContainer
                )
            }

            if showFundingOnAppear {
                isShowingFundingSelection = true
            }
        }
    }

    @ViewBuilder private func toolbarContent() -> some View {
        if let metadata = mintMetadata {
            if metadata.mint == .usdf {
                Text("USD Reserves")
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
        let balance = self.balance
        let appreciation = self.appreciation
        let marketCap = self.marketCap
        let reserveBalance = self.reserveBalance

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

                            CodeButton(style: .filledSecondary, title: "View Transaction History") {
                                isShowingTransactionHistory.toggle()
                            }
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
                    CodeButton(style: .filled, title: "Buy") {
                        isShowingFundingSelection = true
                    }

                    if balance.quarks > 0 {
                        CodeButton(style: .filledSecondary, title: "Sell") {
                            Analytics.buttonTapped(name: .sell)
                            isShowingSellAmountEntry = true
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
                mint: processing.mint,
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
        .sheet(isPresented: $isShowingBuyAmountEntry) {
            CurrencyBuyAmountScreen(viewModel: currencyBuyViewModel)
        }
        .sheet(isPresented: $isShowingSellAmountEntry) {
            if let sellViewModel = currencySellViewModel {
                CurrencySellAmountScreen(viewModel: sellViewModel)
            }
        }
        .sheet(isPresented: $isShowingCurrencySelection) {
            CurrencySelectionScreen(
                isPresented: $isShowingCurrencySelection,
                kind: .balance,
                ratesController: ratesController
            )
        }
        .onChange(of: isShowingBuyAmountEntry) { _, isPresented in
            if isPresented {
                currencyBuyViewModel.reset()
            }
        }
        .onChange(of: isShowingSellAmountEntry) { _, isPresented in
            if isPresented {
                currencySellViewModel?.reset()
            }
        }
        .sheet(isPresented: $isShowingFundingSelection) {
            FundingSelectionSheet(
                reserveBalance: reserveBalance,
                onSelectReserves: {
                    Analytics.buttonTapped(name: .buyWithReserves)
                    isShowingBuyAmountEntry = true
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
