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
    
    @ObservedObject private var viewModel: PoolViewModel
    
    @StateObject private var updateablePool: Updateable<PoolContainer?>
    @StateObject private var updateableBets: Updateable<[BetMetadata]>
    
    @State private var showingConfirmationForBetOutcome: BetOutcome?
    
    private let userID: UserID
    private let poolRendezvous: KeyPair
    private let database: Database
    
    private var poolContainer: PoolContainer? {
        updateablePool.value
    }
    
    private var pool: PoolMetadata? {
        poolContainer?.metadata
    }
    
    private var poolInfo: PoolInfo? {
        poolContainer?.info
    }
    
    private var bets: [BetMetadata] {
        updateableBets.value
    }
    
    private var isHost: Bool {
        pool?.creatorUserID == userID
    }
    
    private var userBet: BetMetadata? {
        bets.filter { $0.userID == userID }.first
    }
    
    private var hasUserBet: Bool {
        userBet != nil
    }
    
    private var amountOnYes: Fiat {
        poolContainer?.amountOnYes ?? 0
    }
    
    private var amountOnNo: Fiat {
        poolContainer?.amountOnNo ?? 0
    }
    
    private var amountInPool: Fiat {
        poolContainer?.amountInPool ?? 0
    }
    
    private var stateForYes: VoteButton.State {
        if let resoltion = pool?.resolution {
            if resoltion == .yes {
                .winner
            } else {
                .normal
            }
        } else if let userBet, userBet.selectedOutcome == .yes {
            .selected
        } else {
            .normal
        }
    }
    
    private var stateForNo: VoteButton.State {
        if let resoltion = pool?.resolution {
            if resoltion == .no {
                .winner
            } else {
                .normal
            }
        } else if let userBet, userBet.selectedOutcome == .no {
            .selected
        } else {
            .normal
        }
    }
    
    // MARK: - Init -
    
    init(userID: UserID, poolRendezvous: KeyPair, database: Database, viewModel: PoolViewModel) {
        self.userID         = userID
        self.poolRendezvous = poolRendezvous
        self.database       = database
        self.viewModel      = viewModel
        
        _updateablePool = .init(wrappedValue: Updateable {
            try? database.getPool(poolID: poolRendezvous.publicKey)
        })
        
        _updateableBets = .init(wrappedValue: Updateable {
            (try? database.getBets(poolID: poolRendezvous.publicKey)) ?? []
        })
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            if let pool {
                poolDetails(pool: pool)
            } else {
                VStack {
                    LoadingView(color: .white)
                }
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
                    flagStyle: amountInPool.currencyCode.flagStyle,
                    content: amountInPool.formatted(suffix: nil),
                    showChevron: false,
                    canScale: false
                )
                .font(.appDisplayMedium)
                
                Text("in pool so far")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 30)
            
            Spacer()
            
            VStack(spacing: 20) {
                HStack {
                    VoteButton(
                        state: stateForYes,
                        name: "Yes",
                        fiat: amountOnYes,
                    ) {
                        showingConfirmationForBetOutcome = .yes
                    }
                    .disabled(hasUserBet)
                    
                    VoteButton(
                        state: stateForNo,
                        name: "No",
                        fiat: amountOnNo
                    ) {
                        showingConfirmationForBetOutcome = .no
                    }
                    .disabled(hasUserBet)
                }
                Text("Tap to buy in")
                    .font(.appDisplayXS)
                    .foregroundStyle(Color.textSecondary)
            }
            
            Spacer()
            
            if isHost {
                VStack(spacing: 0) {
                    CodeButton(
                        style: .filled,
                        title: "Declare the Outcome"
                    ) {
                        
                    }
                    
                    CodeButton(
                        style: .subtle,
                        title: "Share Pool With Friends",
                        action: sharePoolAction
                    )
                }
                .padding(.bottom, -20)
            } else {
                VStack(spacing: 25) {
                    Text("As the pool host, you will decide the outcome of the pool in your sole discretion")
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    CodeButton(
                        style: .filled,
                        title: "Share Pool With Friends",
                        action: sharePoolAction
                    )
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .sheet(item: $showingConfirmationForBetOutcome) { outcome in
            PartialSheet {
                ModalSwipeToBet(
                    fiat: pool.buyIn,
                    subtext: outcome == .yes ? "for Yes" : "for No",
                    swipeText: "Swipe To Pay",
                    cancelTitle: "Cancel"
                ) {
                    try await viewModel.betAction(
                        rendezvous: poolRendezvous,
                        outcome: outcome
                    )
                } dismissAction: {
                    showingConfirmationForBetOutcome = nil
                } cancelAction: {
                    showingConfirmationForBetOutcome = nil
                }
            }
        }
    }
    
    // MARK: - Actions -
    
    private func sharePoolAction() {
        guard let pool, let rendezvous = pool.rendezvous else {
            return
        }
        
        ShareSheet.present(url: .poolLink(rendezvous: rendezvous))
    }
}

// MARK: - VoteButton -

private struct VoteButton: View {
    
    let state: State
    let name: String
    let fiat: Fiat
    let action: () -> Void
    
    private var strokeColor: Color {
        switch state {
        case .normal:
            Metrics.inputFieldStrokeColor(highlighted: false)
        case .selected:
            .clear
        case .winner:
            .clear
        }
    }
    
    private var fillColor: Color {
        switch state {
        case .normal:
            .white.opacity(0.05)
        case .selected:
            .white
        case .winner:
            Color(r: 67, g: 144, b: 84)
        }
    }
    
    private var textColor: Color {
        switch state {
        case .normal:
            .white.opacity(0.6)
        case .selected:
            .backgroundMain
        case .winner:
            .white
        }
    }
    
    init(state: State, name: String, fiat: Fiat, action: @escaping () -> Void) {
        self.state      = state
        self.name       = name
        self.fiat       = fiat
        self.action     = action
    }
    
    var body: some View {
        Button {
            action()
        } label: {
            VStack {
                Text(name)
                    .font(.appDisplaySmall)
                Text(fiat.formatted(suffix: nil))
                    .font(.appTextSmall)
            }
            .foregroundStyle(textColor)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.buttonRadius * 2)
                    .strokeBorder(strokeColor, lineWidth: Metrics.inputFieldBorderWidth(highlighted: false))
                    .fill(fillColor)
            )
        }
    }
}

extension VoteButton {
    enum State {
        case normal
        case selected
        case winner
    }
}
