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
    
    @ObservedObject private var session: Session
    
    private var mintMetadata: StoredMintMetadata {
        updateableMint.value
    }
    
    private var aggregateBalance: AggregateBalance {
        AggregateBalance(
            entryRate: ratesController.rateForEntryCurrency(),
            balanceRate: ratesController.rateForBalanceCurrency(),
            balances: session.balances
        )
    }
    
    private var balance: Fiat {
        aggregateBalance.balanceBalance(for: mint)?.exchangedFiat.converted ?? 0
    }
    
    private let mint: PublicKey
    private let container: Container
    private let ratesController: RatesController
    private let sessionContainer: SessionContainer
    
    private var marketCap: Fiat {
        var supply: Int = 0
        if let supplyFromBonding = mintMetadata.supplyFromBonding {
            supply = Int(supplyFromBonding)
        }
        
        let curve = BondingCurve()
        let mCap  = try! curve.marketCap(for: supply)
        
        return try! Fiat(
            fiatDecimal: mCap,
            currencyCode: ratesController.balanceCurrency,
            decimals: mintMetadata.mint.mintDecimals
        )
    }
    
    // MARK: - Init -
    
    init(mint: PublicKey, container: Container, sessionContainer: SessionContainer) {
        self.mint             = mint
        self.container        = container
        self.ratesController  = sessionContainer.ratesController
        self.session          = sessionContainer.session
        self.sessionContainer = sessionContainer
        
        let database = sessionContainer.database
        
        _updateableMint = .init(wrappedValue: Updateable {
            try! database.getMintMetadata(mint: mint)!
        })
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            GeometryReader { g in
                ScrollView {
                    VStack(spacing: 0) {
                        
                        // Header
                        
                        section {
                            Spacer()
                            
                            AmountText(
                                flagStyle: balance.currencyCode.flagStyle,
                                content: balance.formatted(truncated: true, suffix: nil),
                                showChevron: false
                            )
                            .font(.appDisplayMedium)
                            .foregroundStyle(Color.textMain)
                            .frame(maxWidth: .infinity)
                            
                            Spacer()
                            
                            CodeButton(style: .filledSecondary, title: "View Transaction History") {
                                isShowingTransactionHistory.toggle()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: g.size.height * 0.4)
                        
                        // Currency Info
                        
                        section(spacing: 20) {
                            HStack {
                                Image(systemName: "text.justify.left")
                                    .padding(.bottom, -1)
                                Text("Currency Info")
                            }
                            .font(.appBarButton)
                            .foregroundStyle(Color.textMain)
                            
                            Text(mintMetadata.bio ?? "No information")
                                .foregroundStyle(Color.textSecondary)
                                .font(.appTextSmall)
//                            {
//                                AnyView(drawer())
//                            }
//                            .font(.system(size: 14, weight: .bold))
                        }
                                                    
                        // Market Cap
                            
                        if mintMetadata.mint != .usdc {
                            section(spacing: 0) {
                                VStack(alignment: .leading) {
                                    Text("Market Cap")
                                        .foregroundStyle(Color.textSecondary)
                                        .font(.appTextMedium)
                                    Text("\(marketCap.formatted(suffix: nil))")
                                        .foregroundStyle(Color.textMain)
                                        .font(.appDisplayMedium)
                                }
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
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                CurrencyLabel(
                    imageURL: mintMetadata.imageURL,
                    name: mintMetadata.name,
                    amount: nil
                )
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
