//
//  PoolDetailsScreen.swift
//  Code
//
//  Created by Dima Bart on 2025-06-18.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct PoolDetailsScreen: View {
    
    private let poolID: PublicKey
    
    @StateObject private var updateablePool: Updateable<PoolMetadata?>
    
    private let database: Database
    
    private var pool: PoolMetadata? {
        updateablePool.value
    }
    
    // MARK: - Init -
    
    init(poolID: PublicKey, database: Database) {
        self.poolID = poolID
        self.database = database
        
        _updateablePool = .init(wrappedValue: Updateable {
            try? database.getPool(poolID: poolID)
        })
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            if let pool {
                poolDetails(pool: pool)
            } else {
                LoadingView(color: .white)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder private func poolDetails(pool: PoolMetadata) -> some View {
        VStack {
            Spacer()
            
            Text(pool.name)
                .font(.appTextXL)
                .foregroundStyle(Color.textMain)
            
            Spacer()
                
            VStack(spacing: 10) {
                AmountText(
                    flagStyle: pool.buyIn.currencyCode.flagStyle,
                    content: pool.buyIn.formatted(suffix: nil),
                    showChevron: false,
                    canScale: false
                )
                .font(.appDisplayMedium)
                
                Text("Pool Buy In")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 30)
            
            Spacer()
            
            VStack(spacing: 20) {
                HStack {
                    voteButton(name: "Yes")
                    voteButton(name: "No")
                }
                Text("Tap to buy in")
                    .font(.appDisplayXS)
                    .foregroundStyle(Color.textSecondary)
            }
            
            Spacer()
            
            VStack(spacing: 25) {
                Text("As the pool host, you will decide the outcome of the pool in your sole discretion")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                
                CodeButton(
                    style: .filled,
                    title: "Share Pool With Friends"
                ) {
                    
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(20)
    }
    
    @ViewBuilder private func voteButton(name: String) -> some View {
        Button {
            
        } label: {
            VStack {
                Text(name)
                    .font(.appDisplaySmall)
                Text("$0")
                    .font(.appTextSmall)
            }
            .foregroundStyle(Color.textMain.opacity(0.6))
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.buttonRadius * 2)
                    .strokeBorder(Metrics.inputFieldStrokeColor(highlighted: false), lineWidth: Metrics.inputFieldBorderWidth(highlighted: false))
                    .fill(Color.white.opacity(0.05))
                    .background(
                        Color.backgroundRow
                            .cornerRadius(Metrics.buttonRadius * 2)
                    )
            )
        }
    }
}
