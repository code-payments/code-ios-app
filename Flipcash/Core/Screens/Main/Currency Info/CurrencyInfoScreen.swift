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

    @State private var isShowingTransactionHistory: Bool = false
    @State private var isShowingFundingSelection: Bool = false
    @State private var isShowingBuyAmountEntry: Bool = false
    @State private var isShowingSellAmountEntry: Bool = false
    @State private var chartViewModel: ChartViewModel?
    @State private var isShowingCurrencySelection: Bool = false
    @StateObject private var externalSwapController: ExternalSwapController

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
        guard let mintMetadata else { return 0 }
        let balance   = session.balance(for: mintMetadata.mint)
        let exchanged = balance?.computeExchangedValue(with: ratesController.rateForBalanceCurrency())

        return exchanged?.converted ?? 0
    }

    private var reserveBalance: Quarks {
        let balance   = session.balance(for: .usdf)
        let exchanged = balance?.computeExchangedValue(with: ratesController.rateForBalanceCurrency())

        return exchanged?.converted ?? 0
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

    private let mint: PublicKey
    private let container: Container
    private let ratesController: RatesController
    private let sessionContainer: SessionContainer
    private let marketCapController: MarketCapController

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

    init(mint: PublicKey, container: Container, sessionContainer: SessionContainer) {
        self.mint             = mint
        self.container        = container
        self.ratesController  = sessionContainer.ratesController
        self.session          = sessionContainer.session
        self.sessionContainer = sessionContainer

        _viewModel = .init(wrappedValue: CurrencyInfoViewModel(
            mint: mint,
            sessionContainer: sessionContainer
        ))

        _externalSwapController = .init(
            wrappedValue: ExternalSwapController(walletConnection: sessionContainer.walletConnection)
        )

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
                loadingView()
            case .loaded(let metadata):
                loadedContent(metadata: metadata)
            case .error(let error):
                errorView(error: error)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarContent()
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
        }
    }

    @ViewBuilder private func loadingView() -> some View {
        VStack {
            Spacer()
            LoadingView(color: .textMain)
            Spacer()
        }
    }

    @ViewBuilder private func errorView(error: CurrencyInfoViewModel.Error) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(Color.textSecondary)

            Text(errorTitle(for: error))
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)

            Text(errorSubtitle(for: error))
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            CodeButton(style: .filled, title: "Try Again") {
                Task {
                    await viewModel.loadMintMetadata()
                }
            }
            .padding(20)
        }
    }

    private func errorTitle(for error: CurrencyInfoViewModel.Error) -> String {
        switch error {
        case .mintNotFound:
            return "Currency Not Found"
        case .networkError:
            return "Connection Error"
        }
    }

    private func errorSubtitle(for error: CurrencyInfoViewModel.Error) -> String {
        switch error {
        case .mintNotFound:
            return "This currency could not be found. It may no longer exist."
        case .networkError:
            return "Please check your connection and try again."
        }
    }

    @ViewBuilder private func toolbarContent() -> some View {
        if let metadata = mintMetadata {
            if metadata.mint == .usdf {
                Text("Cash Reserves")
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
        ZStack {
            // Scrollable Content
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

                        if !isUSDF {
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
                        }

                        Text(currencyDescription)
                            .foregroundStyle(Color.textSecondary)
                            .font(.appTextSmall)
                    }

                    // Market Cap
                    if !isUSDF {
                        marketCapSection()

                        // Append enough content to scroll below the floating footer
                        Color
                            .clear
                            .padding(.bottom, 100)
                    }
                }
            }

            // Floating Footer
            if !isUSDF {
                CurrencyInfoScreenFooter {
                    CodeButton(style: .filledAlternative, title: "Buy") {
                        isShowingFundingSelection = true
                    }

                    if balance.quarks > 0 {
                        CodeButton(style: .filledSecondary, title: "Sell") {
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
        .navigationDestination(item: $externalSwapController.processing) { item in
            SwapProcessingScreen(
                swapId: item.swapId,
                swapType: .buy,
                mint: item.mint,
                amount: item.amount
            )
            .environment(\.dismissParentContainer, {
                externalSwapController.dismissProcessing()
            })
        }
        .sheet(isPresented: externalSwapController.isShowingAmountEntry) {
            NavigationStack {
                EnterWalletAmountScreen { quarks in
                    try await externalSwapController.requestSwap(
                        usdc: quarks,
                        mint: metadata.mint,
                        token: metadata.metadata
                    )
                }
                .toolbar {
                    ToolbarCloseButton(binding: externalSwapController.isShowingAmountEntry)
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
        .onChange(of: ratesController.balanceCurrency) { _, _ in
            guard let chartVM = chartViewModel else { return }
            loadChartData(for: chartVM.selectedRange, into: chartVM)
        }
        .sheet(isPresented: $isShowingFundingSelection) {
            PartialSheet {
                VStack {
                    HStack {
                        Text("Select Purchase Method")
                            .font(.appBarButton)
                            .foregroundStyle(Color.textMain)
                        Spacer()
                    }
                    .padding(.vertical, 20)

                    if reserveBalance.quarks > 0 {
                        CodeButton(style: .filled, title: "USDF Reserves (\(reserveBalance))") {
                            isShowingBuyAmountEntry = true
                            isShowingFundingSelection = false
                        }
                    }

                    CodeButton(style: .filledCustom(Image.asset(.phantom), "Phantom"), title: "Solana USDC With") {
                        externalSwapController.connectToPhantom()
                        isShowingFundingSelection = false
                    }
                    CodeButton(style: .subtle, title: "Dismiss") {
                        isShowingFundingSelection = false
                    }
                }
                .padding()
            }
        }
        .dialog(item: externalSwapController.dialogItem)
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
    
    @ViewBuilder private func drawer() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ScrollButton(
                    image: .init(systemName: "network"),
                    text: "Website"
                ) {}
            }
        }
    }
    
    @ViewBuilder private func marketCapSection() -> some View {
        VStack(alignment: .leading) {
            Text("Market Cap")
                .foregroundStyle(Color.textSecondary)
                .font(.appTextMedium)
                .padding(.horizontal, 20)

            if let viewModel = chartViewModel {
                StockChart(
                    viewModel: viewModel,
                    currencyCode: ratesController.balanceCurrency,
                    positiveColor: .actionAlternative,
                    negativeColor: Color(r: 228, g: 42, b: 42)
                )
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 20)
        .task {
            setupChart()
        }
    }
    
    private func setupChart() {
        let viewModel = ChartViewModel(currentValue: marketCap.doubleValue, selectedRange: .all)
        chartViewModel = viewModel

        viewModel.onRangeChange = { [weak viewModel] range in
            guard let viewModel else { return }
            loadChartData(for: range, into: viewModel)
        }

        loadChartData(for: .all, into: viewModel)
    }

    private func loadChartData(for range: ChartRange, into viewModel: ChartViewModel) {
        viewModel.setLoading()
        viewModel.currentValue = marketCap.doubleValue

        Task {
            do {
                let chartPoints = try await marketCapController.fetchChartData(for: range)
                viewModel.setDataPoints(chartPoints, appendingCurrentValue: marketCap.doubleValue)
            } catch let error as ChartError {
                viewModel.setError(error)
            } catch {
                viewModel.setError(.networkError)
            }
        }
    }
}


struct ExpandableText: View {
    @State private var isExpanded: Bool
    
    private let text: String
    private let color: Color
    private let backgroundColor: Color
    private let drawer: (() -> AnyView)?
    
    init(_ text: String, color: Color = Color(r: 155, g: 163, b: 158), backgroundColor: Color = .backgroundMain, expanded: Bool = false, drawer: (() -> AnyView)? = nil) {
        self.text            = text
        self.color           = color
        self.backgroundColor = backgroundColor
        self.drawer          = drawer
        self._isExpanded     = State(initialValue: expanded)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: isExpanded ? nil : 40, alignment: .topLeading)
                .overlay {
                    if !isExpanded {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        backgroundColor,
                                        backgroundColor.opacity(0),
                                    ]),
                                    startPoint: .bottom,
                                    endPoint: UnitPoint(x: 0.5, y: 0.0)
                                )
                            )
                    }
                }
            
            if isExpanded, let drawer = drawer {
                drawer()
                    .padding(.top, 20)
                    .padding(.bottom, 15)
            }
            
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Show \(isExpanded ? "less" : "more")")
                        .frame(width: 78, alignment: .leading)
                    
                    Image(systemName: "chevron.up")
                        .rotationEffect(isExpanded ? .degrees(0) : .degrees(180))
                    
                    Spacer()
                }
                .frame(height: 30)
                .frame(maxWidth: .infinity)
                .background(backgroundColor)
            }
        }
        .clipped()
    }
}

private struct ScrollButton: View {
    let image: Image
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                image
                    .opacity(0.5)
                Text(text)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color(r: 12, g: 37, b: 24))
            .cornerRadius(10)
        }
    }
}

struct CurrencyInfoScreenFooter<Content>: View where Content: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack {
            Spacer()

                HStack(spacing: 12) {
                    content
                }
                .padding(20)
                .background {
                    LinearGradient(
                        gradient: Gradient(colors: [Color.backgroundMain, Color.backgroundMain, .clear]),
                        startPoint: .bottom,
                        endPoint: .top,
                    )
                    .ignoresSafeArea()
                }
        }
    }
}
