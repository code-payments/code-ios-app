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
    private let session: Session
    private let sessionContainer: SessionContainer
    
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
                    VStack {
                        
                        VStack {
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
                                
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: g.size.height * 0.3)
                        .padding(.bottom, 25)
                        .vSeparator(color: .rowSeparator)
                        .padding(.horizontal, 20)
                        
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Image(systemName: "text.justify.left")
                                    .padding(.bottom, -1)
                                Text("Currency Info")
                            }
                            .font(.system(size: 18, weight: .bold))
                            
                            Text(mintMetadata.bio ?? "No information")
                                .font(.system(size: 14, weight: .bold))
                            
//                            ScrollView(.horizontal, showsIndicators: false) {
//                                HStack {
//                                    ScrollButton(
//                                        image: .init(systemName: "network"),
//                                        text: "Website"
//                                    ) {}
//                                }
//                            }
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 25)
                        .vSeparator(color: .rowSeparator)
                        .padding(.horizontal, 20)
                    }
                }
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
