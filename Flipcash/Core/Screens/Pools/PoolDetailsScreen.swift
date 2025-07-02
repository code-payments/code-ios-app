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
    @State private var showingDeclareOutcome: DeclaredOutcome?
    
    @State private var dialogItem: DialogItem?
    
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
    
    private var countOnYes: Int {
        poolContainer?.countOnYes ?? 0
    }
    
    private var countOnNo: Int {
        poolContainer?.countOnNo ?? 0
    }
    
    private var winningsForYes: Fiat {
        poolContainer?.winningsForYes ?? 0
    }
    
    private var winningsForNo: Fiat {
        poolContainer?.winningsForNo ?? 0
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
    
    private var buyIn: Fiat {
        poolContainer?.metadata.buyIn ?? 0
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
        .dialog(item: $dialogItem)
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
            
            VStack(spacing: 0) {
                HStack {
                    VStack(spacing: 0) {
                        VoteButton(
                            state: stateForYes,
                            name: "Yes",
                            fiat: amountOnYes,
                        ) {
                            showingConfirmationForBetOutcome = .yes
                        }
                        .disabled(hasUserBet)
                        .zIndex(1)
                        
                        YouVotedBadge()
                            .offset(y: -Metrics.boxRadius)
                            .zIndex(0)
                            .opacity(userBet?.selectedOutcome == .yes ? 1 : 0)
                    }
                    
                    VStack(spacing: 0) {
                        VoteButton(
                            state: stateForNo,
                            name: "No",
                            fiat: amountOnNo
                        ) {
                            showingConfirmationForBetOutcome = .no
                        }
                        .disabled(hasUserBet)
                        .zIndex(1)
                        
                        YouVotedBadge()
                            .offset(y: -Metrics.boxRadius)
                            .zIndex(0)
                            .opacity(userBet?.selectedOutcome == .no ? 1 : 0)
                    }
                }
                
                if !hasUserBet {
                    Text("Tap to buy in")
                        .font(.appDisplayXS)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, -20) // Offset for YouVotedBadge
                }
            }
            
            Spacer()
            
            if isHost {
                VStack(spacing: 0) {
                    CodeButton(
                        style: .filled,
                        title: "Declare the Outcome"
                    ) {
                        dialogItem = .init(
                            style: .standard,
                            title: "What was the winning outcome?",
                            subtitle: nil,
                            dismissable: true,
                            actions: {
                                .standard("Yes") {
                                    showingDeclareOutcome = .yes
                                };
                                .standard("No") {
                                    showingDeclareOutcome = .no
                                };
                                .outline("Tie (Refund Everyone)") {
                                    showingDeclareOutcome = .tie
                                };
                                .cancel()
                            }
                        )
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
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
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
        .sheet(item: $showingDeclareOutcome) { outcome in
            PartialSheet {
                ModalSwipeToDeclareWinner(
                    outcome: outcome,
                    amount: winningsForDeclaredOutcome(outcome),
                    swipeText: "Swipe To Pay",
                    cancelTitle: "Cancel"
                ) {
                    
                } dismissAction: {
                    showingDeclareOutcome = nil
                } cancelAction: {
                    showingDeclareOutcome = nil
                }
            }
        }
    }
    
    private func winningsForDeclaredOutcome(_ outcome: DeclaredOutcome) -> Fiat {
        switch outcome {
        case .yes:
            winningsForYes
        case .no:
            winningsForNo
        case .tie:
            buyIn
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

private struct YouVotedBadge: View {
    var body: some View {
        VStack {
            Text("You said")
                .font(.appTextSmall)
                .offset(y: Metrics.boxRadius * 0.4)
        }
        .foregroundStyle(.white.opacity(0.6))
        .frame(width: 90, height: 45)
        .background(
            RoundedRectangle(cornerRadius: Metrics.boxRadius)
                .fill(Color.extraLightFill)
                .strokeBorder(Color.lightStroke, lineWidth: Metrics.inputFieldBorderWidth(highlighted: false))
        )
    }
}

// MARK: - Colors -

extension Color {
    static let extraLightFill = Color(r: 12, g: 37, b: 24)
    static let winnerGreen    = Color(r: 67, g: 144, b: 84)
    static let lightStroke    = Color.textSecondary.opacity(0.15)
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
            .lightStroke
        case .selected:
            .clear
        case .winner:
            .clear
        }
    }
    
    private var fillColor: Color {
        switch state {
        case .normal:
            .extraLightFill
        case .selected:
            .white
        case .winner:
            .winnerGreen
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
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.boxRadius)
                    .fill(fillColor)
                    .strokeBorder(strokeColor, lineWidth: 1)
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
