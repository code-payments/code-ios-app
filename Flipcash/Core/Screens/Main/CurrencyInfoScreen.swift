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
    
    @StateObject private var updateableMint: Updateable<StoredMintMetadata>
    
    @State private var isShowingTransactionHistory: Bool = false
    @State private var isShowingFundingSelection: Bool = false
    @State private var isShowingBuyAmountEntry: Bool = false
    @State private var isShowingSellAmountEntry: Bool = false
    @State private var chartViewModel: ChartViewModel?

    @ObservedObject private var session: Session
    @ObservedObject private var walletConnection: WalletConnection
    
    @StateObject private var currencyBuyViewModel: CurrencyBuyViewModel
    @StateObject private var currencySellViewModel: CurrencySellViewModel
    
    private var mintMetadata: StoredMintMetadata {
        updateableMint.value
    }

    private var isUSDF: Bool {
        mintMetadata.mint == .usdf
    }

    private var currencyDescription: String {
        if isUSDF {
            return "Your cash reserves are held in USDF, a fully backed digital dollar supported 1:1 by U.S. dollars. This ensures your funds retain the same value and stability as traditional USD, while benefiting from faster, more transparent transactions on modern financial infrastructure. You can deposit additional funds at any time, or withdraw your USDF for U.S. dollars whenever you like."
        } else {
            return mintMetadata.bio ?? "No information"
        }
    }
    
    private var proportion: CGFloat {
        if isUSDF {
            return 0.24
        } else {
            return 0.35
        }
    }

    private var balance: Quarks {
        let balance   = session.balance(for: mintMetadata.mint)
        let exchanged = balance?.computeExchangedValue(with: ratesController.rateForBalanceCurrency())

        return exchanged?.converted ?? 0
    }
    
    private var reserveBalance: Quarks {
        let balance   = session.balance(for: .usdf)
        let exchanged = balance?.computeExchangedValue(with: ratesController.rateForBalanceCurrency())
        
        return exchanged?.converted ?? 0
    }
    
    private var appreciation: (amount: Quarks, isPositive: Bool)? {
        let balance = session.balance(for: mintMetadata.mint)
        guard let (appreciation, isPositive) = balance?.computeAppreciation(with: ratesController.rateForBalanceCurrency()) else { return nil }
        
        return (appreciation.converted, isPositive)
    }
    
    private let mint: PublicKey
    private let container: Container
    private let ratesController: RatesController
    private let sessionContainer: SessionContainer
    private let marketCapController: MarketCapController
    
    private var marketCap: Quarks {
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
        self.walletConnection = sessionContainer.walletConnection
        
        let database = sessionContainer.database
        let metadata = try! database.getMintMetadata(mint: mint)!
        
        _updateableMint = .init(wrappedValue: Updateable {
            metadata
        })
        
        _currencyBuyViewModel = .init(
            wrappedValue: CurrencyBuyViewModel(
                currencyPublicKey: mint,
                container: container,
                sessionContainer: sessionContainer
            )
        )
        
        _currencySellViewModel = .init(
            wrappedValue: CurrencySellViewModel(
                currencyMetadata: metadata,
                container: container,
                sessionContainer: sessionContainer
            )
        )

        self.marketCapController = MarketCapController(
            mint: mint,
            currencyCode: sessionContainer.ratesController.balanceCurrency.rawValue,
            client: container.client
        )
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            ZStack {
                // Scrollable Content
                GeometryReader { g in
                    ScrollView {
                        VStack(spacing: 0) {
                            // Header

                            section {
                                Spacer()

                                AmountText(
                                    flagStyle: balance.currencyCode.flagStyle,
                                    content: balance.formatted(),
                                    showChevron: false
                                )
                                .font(.appDisplayMedium)
                                .foregroundStyle(Color.textMain)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 20)
                                
                                if !isUSDF, let (amount, isPositive) = appreciation {
                                    ValueAppreciation(amount: amount, isPositive: isPositive)
                                }

                                Spacer()

                                if !isUSDF {
                                    CodeButton(style: .filledSecondary, title: "View Transaction History") {
                                        isShowingTransactionHistory.toggle()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: g.size.height * proportion)

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
    //                            {
    //                                AnyView(drawer())
    //                            }
    //                            .font(.system(size: 14, weight: .bold))
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
                    mintMetadata: mintMetadata,
                    container: container,
                    sessionContainer: sessionContainer
                )
            }
            .sheet(isPresented: $walletConnection.isShowingAmountEntry) {
                NavigationStack {
                    EnterWalletAmountScreen { quarks in
                        try await walletConnection.requestUsdcToUsdfSwap(usdc: quarks, token: mintMetadata.metadata)
                        walletConnection.isShowingAmountEntry = false
                    }
                    .toolbar {
                        ToolbarCloseButton(binding: $walletConnection.isShowingAmountEntry)
                    }
                }
            }
            .sheet(isPresented: $isShowingBuyAmountEntry) {
                NavigationStack {
                    CurrencyBuyAmountScreen(viewModel: currencyBuyViewModel)
                    .toolbar {
                        ToolbarCloseButton(binding: $isShowingBuyAmountEntry)
                    }
                }
            }
            .sheet(isPresented: $isShowingSellAmountEntry) {
                CurrencySellAmountScreen(viewModel: currencySellViewModel)
            }
            .onChange(of: isShowingSellAmountEntry) { _, isPresented in
                if isPresented {
                    currencySellViewModel.reset()
                }
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
                            CodeButton(style: .filled, title: "USD Reserves (\(reserveBalance))") {
                                isShowingBuyAmountEntry = true
                                isShowingFundingSelection = false
                            }
                        }
                        
                        CodeButton(style: .filledCustom(Image.asset(.phantom), "Phantom"), title: "Solana USDF With") {
                            walletConnection.connectToPhantom()
                            isShowingFundingSelection = false
                        }
                        CodeButton(style: .subtle, title: "Dismiss") {
                            isShowingFundingSelection = false
                        }
                    }
                    .padding()
                }
            }
            .dialog(item: $walletConnection.dialogItem)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                if isUSDF {
                    Text("Cash Reserves")
                        .font(.appBarButton)
                        .foregroundStyle(Color.textMain)
                } else {
                    CurrencyLabel(
                        imageURL: mintMetadata.imageURL,
                        name: mintMetadata.name,
                        amount: nil
                    )
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
        if BetaFlags.shared.hasEnabled(.charts) {
            VStack(alignment: .leading) {
                Text("Market Cap")
                    .foregroundStyle(Color.textSecondary)
                    .font(.appTextMedium)
                    .padding(.horizontal, 20)

                if let viewModel = chartViewModel {
                    StockChart(
                        viewModel: viewModel,
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
        } else {
            section() {
                Text("Market Cap")
                    .foregroundStyle(Color.textSecondary)
                    .font(.appTextMedium)
                Text(marketCap.formatted())
                    .foregroundStyle(Color.textMain)
                    .font(.appDisplayMedium)
            }
        }
    }
    
    private func setupChart() {
        let viewModel = ChartViewModel(selectedRange: .all)
        chartViewModel = viewModel

        viewModel.onRangeChange = { [weak viewModel] range in
            guard let viewModel else { return }
            loadChartData(for: range, into: viewModel)
        }

        loadChartData(for: .all, into: viewModel)
    }

    private func loadChartData(for range: ChartRange, into viewModel: ChartViewModel) {
        viewModel.setLoading()

        Task {
            do {
                let chartPoints = try await marketCapController.fetchChartData(for: range)
                viewModel.setDataPoints(chartPoints)
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
